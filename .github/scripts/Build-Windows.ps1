[CmdletBinding()]
param(
    [ValidateSet('x64', 'Win32')]
    [string]$Target = 'x64',

    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

################################################################################
# 1) Basic Environment Checks
################################################################################
if (-not $env:CI) {
    throw "Build-Windows.ps1 requires running in a CI environment."
}

if (-not [System.Environment]::Is64BitOperatingSystem) {
    throw "A 64-bit system is required to build the project on Windows."
}

if ($PSVersionTable.PSVersion -lt [version]"7.2.0") {
    Write-Warning 'This script requires PowerShell Core 7.2 or higher.'
    exit 2
}

################################################################################
# 2) Utility Functions (or dot-source from your utils folder)
################################################################################
function Ensure-Location {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
    Set-Location $Path
}

function Log-Group {
    param([string]$Message = '')
    if ($Message) {
        Write-Host "=== $Message ==="
    } else {
        Write-Host
    }
}

function Invoke-External {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Executable,
        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        $Arguments
    )
    Write-Host "> Running: $Executable $($Arguments -join ' ')"
    & $Executable $Arguments
    if ($LastExitCode -ne 0) {
        throw "$Executable exited with code $LastExitCode"
    }
}

################################################################################
# 3) Optional: vcpkg toolchain file (if used)
################################################################################
$toolchainFile = $null
if ($env:VCPKG_ROOT) {
    $toolchainFile = Join-Path $env:VCPKG_ROOT 'scripts\buildsystems\vcpkg.cmake'
    # Convert toolchain file path to forward slashes:
    $toolchainFile = $toolchainFile -replace '\\', '/'
}

################################################################################
# 4) Main Build Function
################################################################################

function Build-Plugin {
    trap {
        Pop-Location -Stack BuildTemp -ErrorAction 'SilentlyContinue'
        Write-Error $_
        exit 2
    }

    # Assume the repo root (with CMakePresets.json) is two levels up from this script.
    $ScriptHome = $PSScriptRoot
    $ProjectRoot = Resolve-Path "$ScriptHome/../.."
    # Convert project root to forward slashes:
    $ProjectRootStr = $ProjectRoot.ToString() -replace '\\', '/'

    # Create a temporary build folder inside the repo.
    $BuildFolder = Join-Path $ProjectRoot "temp_${Target}"
    Ensure-Location $BuildFolder
    Push-Location -Stack BuildTemp

    # Configure: explicitly tell CMake where the source is (-S) so it finds CMakePresets.json.
    # We set CMAKE_FIND_ROOT_PATH_MODE_PACKAGE to ONLY.
    $CmakeArgs = @(
        '--preset', "windows-ci-${Target}",
        '-S', $ProjectRootStr,
        "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"
    )
    if ($toolchainFile) {
        $CmakeArgs += "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile"
    }
    if ($env:libobs_DIR) {
        # Convert libobs_DIR to forward slashes:
        $fixedLibobs = $env:libobs_DIR -replace '\\', '/'
        $CmakeArgs += "-Dlibobs_DIR=$fixedLibobs"
        $CmakeArgs += "-DCMAKE_PREFIX_PATH=$fixedLibobs"
        # Optionally, you can also add this directory to CMAKE_MODULE_PATH:
        $CmakeArgs += "-DCMAKE_MODULE_PATH=$fixedLibobs"
    } else {
        Write-Host "Warning: libobs_DIR is not set. Plugin build may fail."
    }

    Log-Group "Configuring OBS Plugin with CMake"
    Invoke-External cmake @CmakeArgs

    # Build step using the preset "windows-${Target}".
    $CmakeBuildArgs = @(
        '--build',
        '--preset', "windows-${Target}",
        '--config', $Configuration,
        '--parallel',
        '--', '/consoleLoggerParameters:Summary', '/noLogo'
    )
    Log-Group "Building OBS Plugin"
    Invoke-External cmake @CmakeBuildArgs

    # Install step (optional).
    $CmakeInstallArgs = @(
        '--install', "build_${Target}",
        '--prefix', "$ProjectRootStr/release/$Configuration",
        '--config', $Configuration
    )
    Log-Group "Installing OBS Plugin"
    Invoke-External cmake @CmakeInstallArgs

    Pop-Location -Stack BuildTemp
    Log-Group "Done"
}

################################################################################
# 5) Run the Build
################################################################################
Build-Plugin