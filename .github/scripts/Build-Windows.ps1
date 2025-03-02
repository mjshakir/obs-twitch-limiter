[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string] $Target = 'x64',
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

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
    $ProductName = $BuildSpec.name
    
    # Determine correct paths for dependencies
    $DepsPath = Join-Path -Path $ProjectRoot -ChildPath "dependencies\prebuilt\windows-deps-${DepsVersion}-x64"
    $LibObsPath = Join-Path -Path $DepsPath -ChildPath "lib\cmake\libobs"
    $FrontendApiPath = Join-Path -Path $DepsPath -ChildPath "lib\cmake\obs-frontend-api"
    $W32PthreadsPath = Join-Path -Path $DepsPath -ChildPath "lib\cmake\w32-pthreads"

    # When passing to CMake, normalize path with forward slashes
    $DepsPathCMake = $DepsPath.Replace('\', '/')
    
    Write-Host "Using dependency paths:"
    Write-Host "  Dependencies: $DepsPath"
    Write-Host "  libobs: $LibObsPath"
    Write-Host "  frontend-api: $FrontendApiPath"
    Write-Host "  w32-pthreads: $W32PthreadsPath"
    
    # Ensure vcpkg toolchain path is correct
    $VcpkgRoot = (Resolve-Path ".\vcpkg").Path
    $VcpkgToolchain = Join-Path $VcpkgRoot 'scripts/buildsystems/vcpkg.cmake'
    
    # Add binaries to path so that DLLs can be found
    $env:PATH = "$DepsPath\bin;$env:PATH"
    
    # Build with direct paths
    $CmakeArgs = @(
        "-S", "${ProjectRoot}",
        "-B", "${BuildDir}",
        "-G", "Visual Studio 17 2022",
        "-A", "x64",
        "-DCMAKE_TOOLCHAIN_FILE=${VcpkgToolchain}",
        "-DCMAKE_PREFIX_PATH=${DepsPathCMake}",
        "-DSKIP_DEPENDENCY_RESOLUTION=ON",
        "-DENABLE_FRONTEND_API=ON",
        "-DENABLE_QT=ON",
        "-Dlibobs_DIR=${LibObsPath.Replace('\', '/')}",
        "-Dobs-frontend-api_DIR=${FrontendApiPath.Replace('\', '/')}",
        "-Dw32-pthreads_DIR=${W32PthreadsPath.Replace('\', '/')}",
        "-DOBS_WEBRTC_ENABLED=OFF"
    )
    
    Write-Host "Configuring with CMake..."
    Write-Host "CMake args: $($CmakeArgs -join ' ')"
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