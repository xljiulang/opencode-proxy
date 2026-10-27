$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)
$scriptPath = Join-Path $repoRoot "scripts\smoke-live.ps1"

Describe "smoke-live.ps1" {
  BeforeEach {
    $script:originalKey = $env:OPENCODE_PROXY_API_KEY
  }

  AfterEach {
    $env:OPENCODE_PROXY_API_KEY = $script:originalKey
  }

  It "rejects execution when the API key is missing" {
    $env:OPENCODE_PROXY_API_KEY = $null
    $threw = $false

    try {
      & $scriptPath -Config "missing.toml"
    } catch {
      $threw = $true
      $_.Exception.Message | Should Match "OPENCODE_PROXY_API_KEY"
    }
    $threw | Should Be $true
  }

  It "rejects an explicit config that does not exist" {
    $env:OPENCODE_PROXY_API_KEY = "test-key-present"
    $missing = Join-Path ([IO.Path]::GetTempPath()) "opencode-proxy-missing-$PID.toml"
    $threw = $false

    try {
      & $scriptPath -Config $missing
    } catch {
      $threw = $true
      $_.Exception.Message | Should Match "配置文件不存在"
    }
    $threw | Should Be $true
  }
}
