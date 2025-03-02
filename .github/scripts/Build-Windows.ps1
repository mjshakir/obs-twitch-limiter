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
    $DepsPath = "${ProjectRoot}/dependencies/prebuilt/windows-deps-${DepsVersion}-x64"
    
    # Check environment variables using a different approach due to hyphens
    # Using Get-Item to safely access environment variables with hyphens
    $LibObsPath = ""
    try {
        # Try to get from environment variable if it exists
        $LibObsPath = (Get-Item "env:libobs_DIR" -ErrorAction SilentlyContinue).Value
    } catch {
        # If it fails, use the constructed path
    }
    
    if ([string]::IsNullOrEmpty($LibObsPath)) {
        $LibObsPath = "${DepsPath}/lib/cmake/libobs"
    }
    
    $FrontendApiPath = ""
    try {
        # Using single quotes to treat the entire name as a literal string
        $FrontendApiPath = (Get-Item 'env:obs-frontend-api_DIR' -ErrorAction SilentlyContinue).Value
    } catch {
        # If it fails, use the constructed path
    }
    
    if ([string]::IsNullOrEmpty($FrontendApiPath)) {
        $FrontendApiPath = "${DepsPath}/lib/cmake/obs-frontend-api"
    }
    
    $W32PthreadsPath = ""
    try {
        # Using single quotes to treat the entire name as a literal string
        $W32PthreadsPath = (Get-Item 'env:w32-pthreads_DIR' -ErrorAction SilentlyContinue).Value
    } catch {
        # If it fails, use the constructed path
    }
    
    if ([string]::IsNullOrEmpty($W32PthreadsPath)) {
        $W32PthreadsPath = "${DepsPath}/lib/cmake/w32-pthreads"
    }
    
    # Ensure vcpkg toolchain path is correct
    $VcpkgRoot = (Resolve-Path ".\vcpkg").Path
    $VcpkgToolchain = Join-Path $VcpkgRoot 'scripts/buildsystems/vcpkg.cmake'
    
    # Add binaries to path so that DLLs can be found
    $env:PATH = "$DepsPath\bin;$env:PATH"

    # Convert paths to use forward slashes for CMake
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
        "-S", "${ProjectRoot}",
        "-B", "${BuildDir}",
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