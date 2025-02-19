[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string]$Target = 'x64',
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string]$Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

# Set the VCPKG_ROOT environment variable to the vcpkg directory
$toolchainFile = Join-Path $env:VCPKG_ROOT 'scripts\buildsystems\vcpkg.cmake'

if ($env:CI -eq $null) {
    throw "Build-Windows.ps1 requires CI environment"
}

if (!( [System.Environment]::Is64BitOperatingSystem )) {
    throw "A 64-bit system is required to build the project."
}

if ($PSVersionTable.PSVersion -lt [version]"7.2.0") {
    Write-Warning 'The build script requires PowerShell Core 7 or higher. Please upgrade: https://aka.ms/pscore6'
    exit 2
}

function Build {
    trap {
        Pop-Location -Stack BuildTemp -ErrorAction 'SilentlyContinue'
        Write-Error $_
        exit 2
    }

    $ScriptHome = $PSScriptRoot
    $ProjectRoot = Resolve-Path "$ScriptHome/../.."

    Push-Location -Stack BuildTemp
    Ensure-Location $ProjectRoot

    # Configure using the preset and the toolchain file
    $CmakeArgs = @(
        '--preset', "windows-ci-${Target}",
        "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile",
        "-Dlibobs_DIR=$env:libobs_DIR"
    )

    $CmakeBuildArgs = @(
        '--build', '--preset', "windows-${Target}",
        '--config', $Configuration,
        '--parallel',
        '--', '/consoleLoggerParameters:Summary', '/noLogo'
    )

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

    Pop-Location -Stack BuildTemp
    Log-Group
}

Build