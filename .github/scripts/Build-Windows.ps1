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
    
    # Use the environment variables if they exist, otherwise construct the paths
    # PowerShell requires special syntax for environment variables with hyphens
    $LibObsPath = if ($env:libobs_DIR) { 
        $env:libobs_DIR 
    } else {
        Join-Path -Path $ProjectRoot -ChildPath "dependencies\prebuilt\windows-deps-${DepsVersion}-x64\lib\cmake\libobs"
    }
    
    # For environment variables with hyphens, use the env: drive syntax
    $FrontendApiPath = if (Test-Path env:obs-frontend-api_DIR) { 
        (Get-Item env:obs-frontend-api_DIR).Value 
    } else {
        Join-Path -Path $ProjectRoot -ChildPath "dependencies\prebuilt\windows-deps-${DepsVersion}-x64\lib\cmake\obs-frontend-api"
    }
    
    $W32PthreadsPath = if (Test-Path env:w32-pthreads_DIR) { 
        (Get-Item env:w32-pthreads_DIR).Value 
    } else {
        Join-Path -Path $ProjectRoot -ChildPath "dependencies\prebuilt\windows-deps-${DepsVersion}-x64\lib\cmake\w32-pthreads"
    }
    
    $DepsPath = Join-Path -Path $ProjectRoot -ChildPath "dependencies\prebuilt\windows-deps-${DepsVersion}-x64"
    
    Write-Host "Using dependency paths:"
    Write-Host "  Dependencies: $DepsPath"
    Write-Host "  libobs: $LibObsPath"
    Write-Host "  frontend-api: $FrontendApiPath"
    Write-Host "  w32-pthreads: $W32PthreadsPath"
    
    # Ensure vcpkg toolchain path is correct
    $VcpkgRoot = (Resolve-Path "${ProjectRoot}\vcpkg").Path
    $VcpkgToolchain = Join-Path $VcpkgRoot 'scripts\buildsystems\vcpkg.cmake'
    
    # Add binaries to path so that DLLs can be found
    $env:PATH = "$DepsPath\bin;$env:PATH"
    
    # Convert paths to use forward slashes for CMake
    $ProjectRootCMake = $ProjectRoot.Replace('\', '/')
    $BuildDirCMake = $BuildDir.Replace('\', '/')
    $DepsPathCMake = $DepsPath.Replace('\', '/')
    $LibObsPathCMake = $LibObsPath.Replace('\', '/')
    $FrontendApiPathCMake = $FrontendApiPath.Replace('\', '/')
    $W32PthreadsPathCMake = $W32PthreadsPath.Replace('\', '/')
    $VcpkgToolchainCMake = $VcpkgToolchain.Replace('\', '/')

    Write-Host "Using dependency paths:"
    Write-Host "  Dependencies: $DepsPathCMake"
    Write-Host "  libobs: $LibObsPathCMake"
    Write-Host "  frontend-api: $FrontendApiPathCMake"
    Write-Host "  w32-pthreads: $W32PthreadsPathCMake"
    Write-Host "  Vcpkg toolchain: $VcpkgToolchainCMake"
    
    # Build with direct paths
    $CmakeArgs = @(
        "-S", "${ProjectRootCMake}",
        "-B", "${BuildDirCMake}",
        "-G", "Visual Studio 17 2022",
        "-A", "x64",
        "-DCMAKE_TOOLCHAIN_FILE=${VcpkgToolchainCMake}",
        "-DCMAKE_PREFIX_PATH=${DepsPathCMake}",
        "-DSKIP_DEPENDENCY_RESOLUTION=ON",
        "-DENABLE_FRONTEND_API=ON",
        "-DENABLE_QT=ON",
        "-Dlibobs_DIR=${LibObsPathCMake}",
        "-Dobs-frontend-api_DIR=${FrontendApiPathCMake}",
        "-Dw32-pthreads_DIR=${W32PthreadsPathCMake}",
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