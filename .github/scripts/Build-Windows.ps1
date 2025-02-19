[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string] $Target = 'x64',
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

# Set the vcpkg root (assumes vcpkg was cloned in the repository root)
$env:VCPKG_ROOT = (Resolve-Path ".\vcpkg").Path

# Define the full path to the vcpkg toolchain file
$toolchainFile = Join-Path $env:VCPKG_ROOT 'scripts\buildsystems\vcpkg.cmake'

if ($DebugPreference -eq 'Continue') {
    $VerbosePreference = 'Continue'
    $InformationPreference = 'Continue'
}

if ($env:CI -eq $null) {
    throw "Build-Windows.ps1 requires CI environment"
}

if (-not [System.Environment]::Is64BitOperatingSystem) {
    throw "A 64-bit system is required to build the project."
}

if ($PSVersionTable.PSVersion -lt '7.2.0') {
    Write-Warning 'This build script requires PowerShell Core 7 or later. Please upgrade your PowerShell.'
    exit 2
}

function Build {
    trap {
        Pop-Location -Stack BuildTemp -ErrorAction 'SilentlyContinue'
        Write-Error $_
        exit 2
    }

    $ScriptHome = $PSScriptRoot
    $ProjectRoot = Resolve-Path -Path "$PSScriptRoot/../.."

    # Load any helper functions (if provided)
    $UtilityFunctions = Get-ChildItem -Path $PSScriptRoot\utils.pwsh\*.ps1 -Recurse
    foreach ($Utility in $UtilityFunctions) {
        Write-Debug "Loading $($Utility.FullName)"
        . $Utility.FullName
    }

    Push-Location -Stack BuildTemp
    Set-Location $ProjectRoot

    $CmakeArgs = @(
        '--preset', "windows-ci-${Target}",
        "-DCMAKE_TOOLCHAIN_FILE=${toolchainFile}",
        "-Dlibobs_DIR=${env:libobs_DIR}"
    )

    $CmakeBuildArgs = @('--build')
    $CmakeInstallArgs = @()

    if ($DebugPreference -eq 'Continue') {
        $CmakeArgs += '--debug-output'
        $CmakeBuildArgs += '--verbose'
        $CmakeInstallArgs += '--verbose'
    }

    $CmakeBuildArgs += @(
        '--preset', "windows-${Target}",
        '--config', $Configuration,
        '--parallel',
        '--', '/consoleLoggerParameters:Summary', '/noLogo'
    )

    $CmakeInstallArgs += @(
        '--install', "build_${Target}",
        '--prefix', "${ProjectRoot}\release\$Configuration",
        '--config', $Configuration
    )

    Write-Host "Configuring project with arguments: $CmakeArgs"
    Invoke-External cmake @CmakeArgs

    Write-Host "Building project with arguments: $CmakeBuildArgs"
    Invoke-External cmake @CmakeBuildArgs

    Write-Host "Installing project with arguments: $CmakeInstallArgs"
    Invoke-External cmake @CmakeInstallArgs

    Pop-Location -Stack BuildTemp
}

Build