[CmdletBinding()]
param(
  [string] $Config = "opencode-proxy.toml",
  [string] $Model = $(if ($env:OPENCODE_PROXY_TEST_MODEL) {
      $env:OPENCODE_PROXY_TEST_MODEL
    } else {
      "big-pickle"
    }),
  [ValidateRange(0, 65535)]
  [int] $Port = 0,
  [string] $ProviderPath = "/inference/openai/v1"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Protect-Text {
  param(
    [string] $Text,
    [string] $Secret
  )

  $safe = $Text
  if (-not [string]::IsNullOrEmpty($Secret)) {
    $safe = $safe.Replace($Secret, "<redacted>")
  }
  $safe = [regex]::Replace($safe, "(?i)Bearer\s+\S+", "Bearer <redacted>")
  $safe = [regex]::Replace(
    $safe,
    '(?i)("thread_id"\s*:\s*")[^"]+(")',
    '$1<redacted>$2'
  )
  $safe = [regex]::Replace($safe, "(?i)\bses_[0-9A-Za-z]{26}\b", "ses_<redacted>")
  return $safe
}

function Throw-Redacted {
  param(
    [string] $Message,
    [string] $Secret
  )

  $safe = Protect-Text $Message $Secret
  throw $safe
}

function Get-FreeLoopbackPort {
  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  try {
    $listener.Start()
    return ([Net.IPEndPoint] $listener.LocalEndpoint).Port
  } finally {
    $listener.Stop()
  }
}

function Get-ResponseText {
  param($Response)

  if ($null -eq $Response) {
    return ""
  }
  if ($Response.Content -is [byte[]]) {
    return [Text.Encoding]::UTF8.GetString($Response.Content)
  }
  return [string] $Response.Content
}

$apiKey = $env:OPENCODE_PROXY_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw "OPENCODE_PROXY_API_KEY is required and must not be empty"
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not [IO.Path]::IsPathRooted($Config)) {
  $Config = Join-Path (Get-Location).Path $Config
}
$Config = [IO.Path]::GetFullPath($Config)
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
  throw "配置文件不存在：$Config"
}
$configRelative = [IO.Path]::GetRelativePath($repoRoot, $Config)
if (-not $configRelative.StartsWith("..")) {
  & git -C $repoRoot ls-files --error-unmatch -- $configRelative *> $null
  if ($LASTEXITCODE -eq 0) {
    throw "配置文件必须被 Git 忽略，不能提交真实 org/project：$Config"
  }
}

$codex = Get-Command codex.exe -CommandType Application -ErrorAction SilentlyContinue |
  Select-Object -First 1
if (-not $codex) {
  $codex = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
}
if (-not $codex) {
  throw "Codex CLI was not found on PATH"
}

if ($Port -eq 0) {
  $Port = Get-FreeLoopbackPort
}
$ProviderPath = "/" + $ProviderPath.Trim().Trim("/")
if ($ProviderPath -eq "/") {
  throw "ProviderPath must not be empty"
}

$envFile = Join-Path $repoRoot "target\tools\boringssl-env.cmd"
if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
  throw "BoringSSL environment file not found: $envFile"
}

Write-Host "Building opencode-proxy..."
& cmd.exe /d /c "call `"$envFile`" && cargo build --bin opencode-proxy"
if ($LASTEXITCODE -ne 0) {
  Throw-Redacted "cargo build failed with exit code $LASTEXITCODE" $apiKey
}

$binary = Join-Path $repoRoot "target\debug\opencode-proxy.exe"
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
  throw "opencode-proxy binary not found: $binary"
}

$logDir = Join-Path $repoRoot "target\smoke-live-logs"
$stdoutLog = Join-Path $repoRoot "target\smoke-live.stdout.log"
$stderrLog = Join-Path $repoRoot "target\smoke-live.stderr.log"
$codexOutput = Join-Path $repoRoot "target\smoke-live.codex.jsonl"
$lastMessage = Join-Path $repoRoot "target\smoke-live.last-message.txt"
$process = $null

try {
  $arguments = @(
    "--config", "`"$Config`"",
    "--listen", "127.0.0.1:$Port",
    "--log-dir", "`"$logDir`"",
    "--no-trace"
  )
  Write-Host "Starting proxy on http://127.0.0.1:$Port ..."
  $process = Start-Process -FilePath $binary -ArgumentList $arguments `
    -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

  $baseUrl = "http://127.0.0.1:$Port"
  $health = $null
  for ($attempt = 0; $attempt -lt 100; $attempt++) {
    if ($process.HasExited) {
      $stderr = if (Test-Path $stderrLog) { Get-Content -Raw $stderrLog } else { "" }
      Throw-Redacted "Proxy exited before health check: $stderr" $apiKey
    }
    try {
      $health = Invoke-RestMethod -Uri "$baseUrl/healthz" -TimeoutSec 2
      break
    } catch {
      Start-Sleep -Milliseconds 100
    }
  }
  if ($null -eq $health -or $health.status -ne "ok") {
    throw "Health check did not report status=ok"
  }
  Write-Host "Health check: OK"

  $proxyVars = @(
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
    "http_proxy", "https_proxy", "all_proxy"
  ) | Where-Object {
    -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))
  }
  if ($proxyVars.Count -gt 0) {
    Write-Warning "Network proxy variables are active; this run does not independently verify TLS fingerprint."
  } else {
    Write-Host "Network proxy: disabled"
  }

  $authHeaders = @{ Authorization = "Bearer $apiKey" }
  $modelsUri = "$baseUrl$ProviderPath/models"
  $modelsResponse = Invoke-WebRequest -Uri $modelsUri -Headers $authHeaders `
    -Method Get -SkipHttpErrorCheck -TimeoutSec 60
  $modelsText = Get-ResponseText $modelsResponse
  if ([int] $modelsResponse.StatusCode -ne 200) {
    Throw-Redacted "Models request failed ($($modelsResponse.StatusCode)): $modelsText" $apiKey
  }
  $models = $modelsText | ConvertFrom-Json
  if ($null -eq $models.data -or @($models.data).Count -eq 0) {
    throw "Models response did not contain a non-empty data array"
  }
  Write-Host "Models request: OK ($(@($models.data).Count) models)"

  $sessionId = "smoke-$([Guid]::NewGuid().ToString('N'))"
  $requestBody = @{
    model = $Model
    input = "Reply with exactly OK and do not use tools."
    stream = $true
  } | ConvertTo-Json -Compress
  $responsesResponse = Invoke-WebRequest -Uri "$baseUrl$ProviderPath/responses" `
    -Method Post -Headers ($authHeaders + @{
      "Content-Type" = "application/json"
      "session-id" = $sessionId
    }) -Body $requestBody -SkipHttpErrorCheck -TimeoutSec 180
  $responsesText = Get-ResponseText $responsesResponse
  if ([int] $responsesResponse.StatusCode -ne 200) {
    Throw-Redacted "Responses request failed ($($responsesResponse.StatusCode)): $responsesText" $apiKey
  }
  if (-not $responsesText.Contains("response.completed")) {
    Throw-Redacted "Responses stream did not contain response.completed: $responsesText" $apiKey
  }
  if ($responsesText.Contains("response.failed")) {
    Throw-Redacted "Responses stream contained response.failed: $responsesText" $apiKey
  }
  Write-Host "Responses request: OK (model=$Model)"

  $providerUrl = "$baseUrl$ProviderPath"
  $provider = '{ name = "opencode-proxy", base_url = "' + $providerUrl +
    '", wire_api = "responses", env_key = "OPENCODE_PROXY_API_KEY" }'
  $codexArguments = @(
    "exec",
    "--ephemeral",
    "--ignore-user-config",
    "--json",
    "-C", $repoRoot,
    "-m", $Model,
    "-c", 'model_provider="opencode_proxy"',
    "-c", "model_providers.opencode_proxy=$provider",
    "-o", $lastMessage,
    "Reply with exactly OK and do not use tools."
  )
  Write-Host "Running Codex end-to-end request..."
  $codexLines = & $codex.Source @codexArguments 2>&1 |
    ForEach-Object { Protect-Text ([string] $_) $apiKey }
  $codexExitCode = $LASTEXITCODE
  $codexText = $codexLines -join "`n"
  [IO.File]::WriteAllText($codexOutput, $codexText + "`n", [Text.UTF8Encoding]::new($false))
  if (-not [string]::IsNullOrWhiteSpace($codexText)) {
    Write-Output $codexText
  }
  if ($codexExitCode -ne 0) {
    $tail = Get-Content -LiteralPath $codexOutput -Tail 30 -ErrorAction SilentlyContinue |
      Out-String
    Throw-Redacted "Codex exited with code ${codexExitCode}: $tail" $apiKey
  }
  $final = if (Test-Path -LiteralPath $lastMessage) {
    (Get-Content -Raw $lastMessage).Trim()
  } else {
    ""
  }
  if ($final -ne "OK") {
    Throw-Redacted "Codex final message was not OK: $final" $apiKey
  }
  Write-Host "Codex end-to-end request: OK"
  Write-Host "Live smoke test passed."
} catch {
  Throw-Redacted $_.Exception.Message $apiKey
} finally {
  if ($process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id
    $process.WaitForExit()
  }
}
