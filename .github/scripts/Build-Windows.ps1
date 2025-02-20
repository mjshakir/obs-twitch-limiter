[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string]$Target = 'x64',

    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

if (-not $env:CI) {
    throw "Build-Windows.ps1 requires CI environment"
}

if (-not [System.Environment]::Is64BitOperatingSystem) {
    throw "A 64-bit system is required to build the project."
}

if ($PSVersionTable.PSVersion -lt [version]"7.2.0") {
    Write-Warning 'The build script requires PowerShell Core 7 or higher. Please upgrade: https://aka.ms/pscore6'
    exit 2
}

# Load utility scripts if needed (where 'Ensure-Location' / 'Log-Group' / 'Invoke-External' might be defined)
# $UtilityFunctions = Get-ChildItem -Path "$PSScriptRoot\utils.pwsh" -Filter *.ps1 -Recurse
# foreach ($Utility in $UtilityFunctions) {
#     . $Utility.FullName
# }

# If you're using vcpkg:
$toolchainFile = $null
if ($env:VCPKG_ROOT) {
    $toolchainFile = Join-Path $env:VCPKG_ROOT 'scripts\buildsystems\vcpkg.cmake'
}

function Build-Plugin {
    trap {
        Pop-Location -Stack BuildTemp -ErrorAction 'SilentlyContinue'
        Write-Error $_
        exit 2
    }

    $ScriptHome = $PSScriptRoot
    $ProjectRoot = Resolve-Path "$ScriptHome/../.."

    # If you want a separate temp folder:
    $BuildFolder = Join-Path $ProjectRoot "temp_${Target}"
    if (-not (Test-Path $BuildFolder)) {
        New-Item -ItemType Directory -Path $BuildFolder | Out-Null
    }

    # Push that build folder as our working directory
    Push-Location -Stack BuildTemp
    Set-Location $BuildFolder

    # We'll explicitly point cmake to $ProjectRoot (where CMakePresets.json is).
    $CmakeArgs = @(
        '--preset', "windows-ci-${Target}",
        '-S', $ProjectRoot  # <--- The big fix: read presets from $ProjectRoot
    )
    if ($toolchainFile) {
        $CmakeArgs += "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile"
    }
    if ($env:libobs_DIR) {
        $CmakeArgs += "-Dlibobs_DIR=$env:libobs_DIR"
    }

    # e.g. Log-Group "Configuring Plugin..." # if you have that function
    Invoke-External cmake @CmakeArgs

    # Build command: 'cmake --build --preset windows-x64' or the same preset name
    $CmakeBuildArgs = @(
        '--build', 
        '--preset', "windows-${Target}",
        '--config', $Configuration,
        '--parallel',
        '--', '/consoleLoggerParameters:Summary', '/noLogo'
    )
    Invoke-External cmake @CmakeBuildArgs

    # Or install
    $CmakeInstallArgs = @(
        '--install', "build_${Target}",
        '--prefix', "$ProjectRoot/release/$Configuration",
        '--config', $Configuration
    )
    Invoke-External cmake @CmakeInstallArgs

    Pop-Location -Stack BuildTemp
}

Build-Plugin