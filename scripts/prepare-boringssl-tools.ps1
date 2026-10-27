[CmdletBinding()]
param(
  [string] $ToolsDir,
  [string] $EnvFile,
  [switch] $ForceDownload
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (-not [Environment]::Is64BitOperatingSystem) {
  throw "BoringSSL build tools require 64-bit Windows"
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if ([string]::IsNullOrWhiteSpace($ToolsDir)) {
  $ToolsDir = Join-Path $repoRoot "target\tools"
} elseif (-not [IO.Path]::IsPathRooted($ToolsDir)) {
  $ToolsDir = Join-Path (Get-Location).Path $ToolsDir
}
$ToolsDir = [IO.Path]::GetFullPath($ToolsDir)

if ([string]::IsNullOrWhiteSpace($EnvFile)) {
  $EnvFile = Join-Path $ToolsDir "boringssl-env.cmd"
} elseif (-not [IO.Path]::IsPathRooted($EnvFile)) {
  $EnvFile = Join-Path (Get-Location).Path $EnvFile
}
$EnvFile = [IO.Path]::GetFullPath($EnvFile)

$downloadDir = Join-Path $ToolsDir "downloads"
$nasmVersion = "3.01"
$nasmArchiveName = "nasm-$nasmVersion-win64.zip"
$nasmArchive = Join-Path $downloadDir $nasmArchiveName
$nasmArchiveUri =
  "https://www.nasm.us/pub/nasm/releasebuilds/$nasmVersion/win64/$nasmArchiveName"
$nasmArchiveSha256 =
  "e0ba5157007abc7b1a65118a96657a961ddf55f7e3f632ee035366dfce039ca4"
$nasmExeSha256 =
  "5f59c792cc3b92316a4e6d61cae192588a0d8f8fa30b33988a0f2230e5a9c22c"
$nasmCache = Join-Path $ToolsDir "nasm-$nasmVersion"
$nasmCacheExe = Join-Path $nasmCache "nasm.exe"

$libclangVersion = "18.1.3.2"
$libclangPackageName = "libclang.runtime.win-x64.$libclangVersion.nupkg"
$libclangPackage = Join-Path $downloadDir $libclangPackageName
$libclangPackageUri =
  "https://api.nuget.org/v3-flatcontainer/libclang.runtime.win-x64/$libclangVersion/$libclangPackageName"
$libclangPackageSha256 =
  "524e5cce91f43a74d5bbf57debc42c11b87e8fa86f1fc95be7375dd67b427e18"
$libclangCache = Join-Path $ToolsDir "libclang-$libclangVersion"
$libclangCacheDir = Join-Path $libclangCache "runtimes\win-x64\native"
$libclangCacheDll = Join-Path $libclangCacheDir "libclang.dll"
$libclangDllSha256 =
  "b7177fdd6a9c8ed2a8bebf2be54372ddba72e5a6ff9a19d57339c0f83948dce6"

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EnvFile) | Out-Null

function Test-WindowsExecutable {
  param([string] $Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or
      -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }

  $stream = $null
  $reader = $null
  try {
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    if ($reader.ReadUInt16() -ne 0x5A4D) {
      return $false
    }
    $stream.Position = 0x3C
    $peOffset = $reader.ReadInt32()
    if ($peOffset -lt 0 -or $peOffset -gt $stream.Length - 6) {
      return $false
    }
    $stream.Position = $peOffset
    if ($reader.ReadUInt32() -ne 0x00004550) {
      return $false
    }
    $machine = $reader.ReadUInt16()
    return $machine -eq 0x014C -or $machine -eq 0x8664
  } catch {
    return $false
  } finally {
    if ($reader) {
      $reader.Dispose()
    } elseif ($stream) {
      $stream.Dispose()
    }
  }
}

function Test-Executable {
  param(
    [string] $Path,
    [string[]] $Arguments = @("--version")
  )

  if ([string]::IsNullOrWhiteSpace($Path) -or
      -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }
  if (-not (Test-WindowsExecutable $Path)) {
    return $false
  }

  try {
    & $Path @Arguments *> $null
    return $LASTEXITCODE -eq 0
  } catch {
    return $false
  }
}

function Test-Nasm {
  param([string] $Path)
  return Test-Executable -Path $Path -Arguments @("-v")
}

function Test-LibclangDir {
  param([string] $Directory)

  if ([string]::IsNullOrWhiteSpace($Directory)) {
    return $false
  }
  return Test-Path -LiteralPath (Join-Path $Directory "libclang.dll") -PathType Leaf
}

function Test-PortableNasm {
  if (-not (Test-Path -LiteralPath $nasmCacheExe -PathType Leaf)) {
    return $false
  }
  try {
    Assert-FileHash -Path $nasmCacheExe -Expected $nasmExeSha256
  } catch {
    return $false
  }
  return Test-Nasm $nasmCacheExe
}

function Test-PortableLibclang {
  if (-not (Test-Path -LiteralPath $libclangCacheDll -PathType Leaf)) {
    return $false
  }
  try {
    Assert-FileHash -Path $libclangCacheDll -Expected $libclangDllSha256
    return $true
  } catch {
    return $false
  }
}

function Get-SystemNasm {
  $configured = $env:CMAKE_ASM_NASM_COMPILER
  if (Test-Nasm $configured) {
    return $configured
  }

  $command = Get-Command nasm.exe -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($command -and (Test-Nasm $command.Source)) {
    return $command.Source
  }

  $candidates = @(
    (Join-Path $env:ProgramFiles "NASM\nasm.exe")
  )
  if (${env:ProgramFiles(x86)}) {
    $candidates += Join-Path ${env:ProgramFiles(x86)} "NASM\nasm.exe"
  }
  if ($env:ProgramData) {
    $candidates += Join-Path $env:ProgramData "chocolatey\bin\nasm.exe"
  }

  foreach ($candidate in $candidates) {
    if (Test-Nasm $candidate) {
      return $candidate
    }
  }
  return $null
}

function Get-SystemLibclangDir {
  $candidates = @()
  if ($env:LIBCLANG_PATH) {
    $candidates += $env:LIBCLANG_PATH
  }

  $clang = Get-Command clang.exe -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($clang) {
    $candidates += Split-Path -Parent $clang.Source
  }

  $candidates += Join-Path $env:ProgramFiles "LLVM\bin"

  foreach ($candidate in $candidates) {
    if (Test-LibclangDir $candidate) {
      return $candidate
    }
  }
  return $null
}

function Get-VisualStudioLibclangDir {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
    $vsPath = & $vswhere -latest -products * -property installationPath
    if ($vsPath) {
      $llvmRoot = Join-Path $vsPath "VC\Tools\Llvm"
      if (Test-Path -LiteralPath $llvmRoot -PathType Container) {
        $dll = Get-ChildItem -LiteralPath $llvmRoot -Recurse -Filter libclang.dll `
          -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dll) {
          return Split-Path -Parent $dll.FullName
        }
      }
    }
  }
  return $null
}

function Get-CmakePath {
  $command = Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($command -and (Test-Executable -Path $command.Source -Arguments @("--version"))) {
    return $command.Source
  }

  $candidates = @(
    (Join-Path $env:ProgramFiles "CMake\bin\cmake.exe")
  )
  foreach ($candidate in $candidates) {
    if (Test-Executable -Path $candidate -Arguments @("--version")) {
      return $candidate
    }
  }
  return $null
}

function Assert-FileHash {
  param(
    [string] $Path,
    [string] $Expected
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
  }
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $Expected.ToLowerInvariant()) {
    throw "SHA-256 mismatch: $Path`nExpected: $Expected`nActual: $actual"
  }
}

function Get-VerifiedDownload {
  param(
    [string] $Uri,
    [string] $Destination,
    [string] $Sha256
  )

  if (-not $ForceDownload -and (Test-Path -LiteralPath $Destination -PathType Leaf)) {
    try {
      Assert-FileHash -Path $Destination -Expected $Sha256
      Write-Host "Using cached download: $Destination"
      return
    } catch {
      Write-Warning "Cached download is invalid; downloading again: $Destination"
      Remove-Item -LiteralPath $Destination -Force
    }
  }

  $temporary = "$Destination.download"
  if (Test-Path -LiteralPath $temporary) {
    Remove-Item -LiteralPath $temporary -Force
  }

  Write-Host "Downloading: $Uri"
  try {
    [Net.ServicePointManager]::SecurityProtocol =
      [Net.ServicePointManager]::SecurityProtocol -bor
      [Net.SecurityProtocolType]::Tls12
  } catch {
    # PowerShell 7 enables TLS 1.2+ by default.
  }
  Invoke-WebRequest -Uri $Uri -OutFile $temporary -UseBasicParsing
  Assert-FileHash -Path $temporary -Expected $Sha256
  Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

function Remove-CacheDirectory {
  param([string] $Path)

  $fullPath = [IO.Path]::GetFullPath($Path)
  $rootWithSeparator = $ToolsDir.TrimEnd('\') + '\'
  if (-not $fullPath.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean a path outside ToolsDir: $fullPath"
  }
  if (Test-Path -LiteralPath $fullPath) {
    Remove-Item -LiteralPath $fullPath -Recurse -Force
  }
}

function Ensure-PortableNasm {
  if (-not $ForceDownload -and (Test-PortableNasm)) {
    return $nasmCacheExe
  }

  Get-VerifiedDownload -Uri $nasmArchiveUri -Destination $nasmArchive `
    -Sha256 $nasmArchiveSha256

  $staging = Join-Path $ToolsDir ".nasm-staging-$PID"
  Remove-CacheDirectory $staging
  Remove-CacheDirectory $nasmCache
  try {
    Expand-Archive -LiteralPath $nasmArchive -DestinationPath $staging -Force
    $extracted = Get-ChildItem -LiteralPath $staging -Recurse -Filter nasm.exe |
      Select-Object -First 1
    if (-not $extracted) {
      throw "nasm.exe was not found in the NASM archive"
    }
    $extractedRoot = Split-Path -Parent $extracted.FullName
    Move-Item -LiteralPath $extractedRoot -Destination $nasmCache
  } finally {
    Remove-CacheDirectory $staging
  }

  Assert-FileHash -Path $nasmCacheExe -Expected $nasmExeSha256
  if (-not (Test-Nasm $nasmCacheExe)) {
    throw "Portable NASM is not executable: $nasmCacheExe"
  }
  return $nasmCacheExe
}

function Ensure-PortableLibclang {
  if (-not $ForceDownload -and (Test-PortableLibclang)) {
    return $libclangCacheDir
  }

  Get-VerifiedDownload -Uri $libclangPackageUri -Destination $libclangPackage `
    -Sha256 $libclangPackageSha256

  $staging = Join-Path $ToolsDir ".libclang-staging-$PID"
  Remove-CacheDirectory $staging
  Remove-CacheDirectory $libclangCache
  try {
    Expand-Archive -LiteralPath $libclangPackage -DestinationPath $staging -Force
    if (-not (Test-Path -LiteralPath (Join-Path $staging "runtimes\win-x64\native\libclang.dll") `
        -PathType Leaf)) {
      throw "libclang.dll was not found in the NuGet package"
    }
    Move-Item -LiteralPath $staging -Destination $libclangCache
  } finally {
    Remove-CacheDirectory $staging
  }

  Assert-FileHash -Path $libclangCacheDll -Expected $libclangDllSha256
  if (-not (Test-LibclangDir $libclangCacheDir)) {
    throw "Portable libclang directory is invalid: $libclangCacheDir"
  }
  return $libclangCacheDir
}

$nasmPath = $null
if (-not $ForceDownload) {
  $nasmPath = Get-SystemNasm
}
if (-not (Test-Nasm $nasmPath)) {
  $nasmPath = Ensure-PortableNasm
}

$libclangDir = $null
if (-not $ForceDownload) {
  $libclangDir = Get-SystemLibclangDir
}
  if (-not (Test-LibclangDir $libclangDir)) {
    if (-not (Test-PortableLibclang)) {
      $libclangDir = Get-VisualStudioLibclangDir
    }
  }
  if (-not (Test-LibclangDir $libclangDir)) {
    $libclangDir = Ensure-PortableLibclang
  }

$cmakePath = Get-CmakePath
if (-not $cmakePath) {
  throw "CMake 3.22+ was not found. Install it and add it to PATH."
}

$nasmDir = Split-Path -Parent $nasmPath
$cmakeDir = Split-Path -Parent $cmakePath
function Escape-CmdValue {
  param([string] $Value)
  return $Value.Replace("%", "%%")
}

$envContent = @(
  "@echo off",
  ('set "CMAKE={0}"' -f (Escape-CmdValue $cmakePath)),
  ('set "CMAKE_ASM_NASM_COMPILER={0}"' -f (Escape-CmdValue $nasmPath)),
  ('set "LIBCLANG_PATH={0}"' -f (Escape-CmdValue $libclangDir)),
  ('set "PATH={0};{1};%PATH%"' -f
    (Escape-CmdValue $cmakeDir),
    (Escape-CmdValue $nasmDir)),
  ""
) -join "`r`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($EnvFile, $envContent, $utf8NoBom)

Write-Host "BoringSSL build tools are ready:"
Write-Host "  CMake:   $cmakePath"
Write-Host "  NASM:    $nasmPath"
Write-Host "  libclang: $libclangDir"
Write-Host "  Env file:   $EnvFile"
