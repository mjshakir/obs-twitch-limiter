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
# 2) Utility Functions
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
# 3) Main Build Function
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
    # Convert ProjectRoot to forward slashes:
    $ProjectRootStr = $ProjectRoot.ToString() -replace '\\', '/'

    # Create (or reuse) a temporary build folder in the repo.
    $BuildFolder = Join-Path $ProjectRoot "temp_${Target}"
    Ensure-Location $BuildFolder
    Push-Location -Stack BuildTemp

    # Configure: tell CMake where the source is and explicitly provide the OBS install path.
    # We omit the vcpkg toolchain here to avoid interference.
    $CmakeArgs = @(
        '--preset', "windows-ci-${Target}",
        '-S', $ProjectRootStr,
        "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"
    )
    if ($env:libobs_DIR) {
        # Convert libobs_DIR to forward slashes.
        $fixedLibobs = $env:libobs_DIR -replace '\\', '/'
        $CmakeArgs += "-Dlibobs_DIR=$fixedLibobs"
        $CmakeArgs += "-DCMAKE_PREFIX_PATH=$fixedLibobs"
        $CmakeArgs += "-DCMAKE_MODULE_PATH=$fixedLibobs"
    } else {
        Write-Host "Warning: libobs_DIR is not set. Plugin build may fail."
    }

    Log-Group "Configuring OBS Plugin with CMake"
    Invoke-External cmake @CmakeArgs

    # Build step using the build preset "windows-${Target}".
    $CmakeBuildArgs = @(
        '--build',
        '--preset', "windows-${Target}",
        '--config', $Configuration,
        '--parallel',
        '--', '/consoleLoggerParameters:Summary', '/noLogo'
    )
    Log-Group "Building OBS Plugin"
    Invoke-External cmake @CmakeBuildArgs

    # (Optional) Install step.
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
# Run the Build
################################################################################
Build-Plugin