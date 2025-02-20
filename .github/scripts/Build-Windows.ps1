[CmdletBinding()]
param(
    [ValidateSet('x64', 'Win32')]
    [string]$Target = 'x64',

    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

if (-not $env:CI) {
    throw "Build-Windows.ps1 requires a CI environment"
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "A 64-bit system is required to build the project."
}

if ($PSVersionTable.PSVersion -lt [version]"7.2.0") {
    Write-Warning 'This script requires PowerShell 7.2 or higher.'
    exit 2
}

# ------------------------------------------------------------------------------
# Load Utility Scripts
# ------------------------------------------------------------------------------
# We assume you have a folder:  .github/scripts/utils.pwsh/
# containing: Ensure-Location.ps1, Invoke-External.ps1, Log-Group.ps1, etc.
# This snippet loads them at runtime, so all helper functions are available.
# ------------------------------------------------------------------------------
$UtilityFunctions = Get-ChildItem -Path "$PSScriptRoot\utils.pwsh" -Filter *.ps1 -Recurse
foreach ($Utility in $UtilityFunctions) {
    Write-Host "Loading utility script: $($Utility.FullName)"
    . $Utility.FullName
}

# If you need to define $toolchainFile for vcpkg:
if ($env:VCPKG_ROOT) {
    $toolchainFile = Join-Path $env:VCPKG_ROOT 'scripts\buildsystems\vcpkg.cmake'
} else {
    $toolchainFile = $null
}

function Build-Plugin {
    trap {
        # If anything fails, pop the location stack so we don't leave the shell stuck in a subdir
        Pop-Location -Stack BuildTemp -ErrorAction 'SilentlyContinue'
        Write-Error $_
        exit 2
    }

    $ScriptHome = $PSScriptRoot
    # Typically your plugin repo root is two levels up from this script
    $ProjectRoot = Resolve-Path "$ScriptHome/../.."

    # Create a subdirectory for temporary build usage (if desired)
    # Then push it onto a directory stack named BuildTemp
    $BuildTemp = Join-Path $ProjectRoot "temp_$Target"
    Ensure-Location $BuildTemp
    Push-Location -Stack BuildTemp

    # --- Configure arguments for "cmake --preset" approach ---
    $CmakeArgs = @(
        '--preset', "windows-ci-${Target}"
    )

    # If your plugin uses vcpkg or needs to find libobs, add them:
    if ($toolchainFile) {
        $CmakeArgs += "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile"
    }
    if ($env:libobs_DIR) {
        $CmakeArgs += "-Dlibobs_DIR=$env:libobs_DIR"
    }

    # --- Build arguments ---
    $CmakeBuildArgs = @(
        '--build', 
        '--preset', "windows-${Target}",
        '--config', $Configuration,
        '--parallel',
        '--', '/consoleLoggerParameters:Summary', '/noLogo'
    )

    # --- Install arguments (optional) ---
    $CmakeInstallArgs = @(
        '--install', "build_${Target}",
        '--prefix', "$ProjectRoot/release/$Configuration",
        '--config', $Configuration
    )

    Log-Group "Configuring OBS Plugin..."
    Invoke-External cmake @CmakeArgs

    Log-Group "Building OBS Plugin..."
    Invoke-External cmake @CmakeBuildArgs

    Log-Group "Installing OBS Plugin..."
    Invoke-External cmake @CmakeInstallArgs

    # Return to original directory
    Pop-Location -Stack BuildTemp
    Log-Group
}

Build-Plugin