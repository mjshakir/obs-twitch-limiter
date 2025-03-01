[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string] $Target = 'x64',
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

#Set the vcpkg root (adjust if necessary)
$env:VCPKG_ROOT = (Resolve-Path ".\vcpkg").Path

# Define the full path to the vcpkg toolchain file
# $toolchainFile = Join-Path ${env:VCPKG_ROOT} 'scripts\buildsystems\vcpkg.cmake'

$env:CMAKE_TOOLCHAIN_FILE = Join-Path $env:VCPKG_ROOT "scripts\buildsystems\vcpkg.cmake"


if ( $DebugPreference -eq 'Continue' ) {
    $VerbosePreference = 'Continue'
    $InformationPreference = 'Continue'
}

if ( $env:CI -eq $null ) {
    throw "Build-Windows.ps1 requires CI environment"
}

if ( ! ( [System.Environment]::Is64BitOperatingSystem ) ) {
    throw "A 64-bit system is required to build the project."
}

if ( $PSVersionTable.PSVersion -lt '7.2.0' ) {
    Write-Warning 'The obs-studio PowerShell build script requires PowerShell Core 7. Install or upgrade your PowerShell version: https://aka.ms/pscore6'
    exit 2
}

function Build {
    $ProjectRoot = Resolve-Path -Path "$PSScriptRoot/../.."
    $BuildDir = "${ProjectRoot}/build_x64"
    
    # Create build directory
    if (!(Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir | Out-Null
    }
    
    # Read the dependency version from buildspec
    $BuildSpec = Get-Content -Path "${ProjectRoot}/buildspec.json" -Raw | ConvertFrom-Json
    $DepsVersion = $BuildSpec.dependencies.prebuilt.version
    
    # Determine correct paths for dependencies
    $DepsPath = "${ProjectRoot}/dependencies/prebuilt/windows-deps-${DepsVersion}-x64"
    $LibObsPath = "${DepsPath}/lib/cmake/libobs"
    $FrontendApiPath = "${DepsPath}/lib/cmake/obs-frontend-api"
    
    Write-Host "Using dependency paths:"
    Write-Host "  Dependencies: $DepsPath"
    Write-Host "  libobs: $LibObsPath"
    Write-Host "  frontend-api: $FrontendApiPath"
    
    # Ensure vcpkg toolchain path is correct
    $VcpkgToolchain = Join-Path ${Env:VCPKG_ROOT} 'scripts/buildsystems/vcpkg.cmake'
    
    # Build with direct paths
    $CmakeArgs = @(
        "-S", "${ProjectRoot}",
        "-B", "${BuildDir}",
        "-G", "Visual Studio 17 2022",
        "-A", "x64",
        "-DCMAKE_TOOLCHAIN_FILE=${VcpkgToolchain}",
        "-DCMAKE_PREFIX_PATH=${DepsPath}",
        "-DENABLE_FRONTEND_API=ON",
        "-DENABLE_QT=ON",
        "-Dlibobs_DIR=${LibObsPath}",
        "-Dobs-frontend-api_DIR=${FrontendApiPath}",
        "-DSKIP_DEPENDENCY_RESOLUTION=ON"
    )
    
    Write-Host "Configuring with CMake..."
    Write-Host "CMake args: $CmakeArgs"
    & cmake @CmakeArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "CMake configuration failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    
    Write-Host "Building project..."
    & cmake --build "${BuildDir}" --config $Configuration --parallel
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    
    Write-Host "Installing project..."
    & cmake --install "${BuildDir}" --prefix "${ProjectRoot}/release/${Configuration}" --config $Configuration
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Installation failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

Build