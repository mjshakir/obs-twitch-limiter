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
# 2) Utility Functions (Normally in utils.pwsh/*.ps1)
#    If you have these in separate .ps1 files, dot-source them instead:
#
#    $UtilityFunctions = Get-ChildItem -Path "$PSScriptRoot\utils.pwsh" -Filter *.ps1 -Recurse
#    foreach ($Utility in $UtilityFunctions) {
#        . $Utility.FullName
#    }
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
    param(
        [Parameter(Mandatory=$false)][string]$Message = ''
    )
    # Minimal example: just write a heading
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
# 3) Optional: If using vcpkg
################################################################################

$toolchainFile = $null
if ($env:VCPKG_ROOT) {
    $toolchainFile = Join-Path $env:VCPKG_ROOT 'scripts\buildsystems\vcpkg.cmake'
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

    $ScriptHome = $PSScriptRoot
    # Typically your plugin's root is two levels up: <repo>/.github/scripts/Build-Windows.ps1
    $ProjectRoot = Resolve-Path "$ScriptHome/../.."

    # 4.1) Create or reuse a "temp_{Target}" folder for an out-of-tree build
    $BuildFolder = Join-Path $ProjectRoot "temp_${Target}"
    Ensure-Location $BuildFolder
    Push-Location -Stack BuildTemp

    # 4.2) Configure the plugin via CMake presets (CMakePresets.json is in $ProjectRoot)
    $CmakeArgs = @(
        '--preset', "windows-ci-${Target}",
        '-S', $ProjectRoot  # The directory with CMakePresets.json
    )

    if ($toolchainFile) {
        $CmakeArgs += "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile"
    }
    if ($env:libobs_DIR) {
        $CmakeArgs += "-Dlibobs_DIR=$env:libobs_DIR"
    }

    Log-Group "Configuring OBS Plugin with CMake"
    Invoke-External cmake @CmakeArgs

    # 4.3) Build using the preset "windows-${Target}"
    $CmakeBuildArgs = @(
        '--build',
        '--preset', "windows-${Target}",
        '--config', $Configuration,
        '--parallel',
        '--', '/consoleLoggerParameters:Summary', '/noLogo'
    )

    Log-Group "Building OBS Plugin"
    Invoke-External cmake @CmakeBuildArgs

    # 4.4) Optionally install the plugin to release/<Configuration>
    #      (If you don't need an install step, you can remove this.)
    $CmakeInstallArgs = @(
        '--install', "build_${Target}",
        '--prefix', "$ProjectRoot/release/$Configuration",
        '--config', $Configuration
    )

    Log-Group "Installing OBS Plugin"
    Invoke-External cmake @CmakeInstallArgs

    Pop-Location -Stack BuildTemp
    Log-Group "Done"
}

################################################################################
# 5) Actually run the build
################################################################################
Build-Plugin