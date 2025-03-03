[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string] $Target = 'x64',
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

function Build {
    $ProjectRoot = (Resolve-Path -Path "$PSScriptRoot/../..").Path
    $BuildDir = "${ProjectRoot}/build_x64"
    
    # Create build directory
    if (!(Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir | Out-Null
    }
    
    # Read the dependency version from buildspec
    $BuildSpec = Get-Content -Path "${ProjectRoot}/buildspec.json" -Raw | ConvertFrom-Json
    $DepsVersion = $BuildSpec.dependencies.prebuilt.version
    $ProductName = $BuildSpec.name
    
    # Get the base dependencies directory
    $DepsPath = Join-Path -Path $ProjectRoot -ChildPath "dependencies\prebuilt\windows-deps-${DepsVersion}-x64"
    
    # Check .deps directory (this seems to be where libobsConfig.cmake is found)
    $DotDepsPath = Join-Path -Path $ProjectRoot -ChildPath ".deps"
    $DotDepsConfigPath = Join-Path -Path $DotDepsPath -ChildPath "cmake"
    
    Write-Host "Looking for configuration files in .deps directory..."
    if (Test-Path $DotDepsConfigPath) {
        Get-ChildItem -Path $DotDepsConfigPath -Filter "*Config.cmake" | ForEach-Object {
            Write-Host "  Found config file: $($_.Name)"
        }
    }
    
    # Try to find w32-pthreads specifically
    $W32PthreadsPath = $null
    $W32PthreadsPaths = @(
        # Check standard locations
        "${ProjectRoot}\dependencies\prebuilt\windows-deps-${DepsVersion}-x64\lib\cmake\w32-pthreads",
        "${DotDepsPath}\lib\cmake\w32-pthreads",
        "${DotDepsPath}\cmake"
    )
    
    foreach ($Path in $W32PthreadsPaths) {
        $ConfigFile = Join-Path -Path $Path -ChildPath "w32-pthreadsConfig.cmake"
        if (Test-Path $ConfigFile) {
            $W32PthreadsPath = $Path
            Write-Host "Found w32-pthreadsConfig.cmake at: $ConfigFile"
            break
        }
        
        $ConfigFile = Join-Path -Path $Path -ChildPath "w32-pthreads-config.cmake"
        if (Test-Path $ConfigFile) {
            $W32PthreadsPath = $Path
            Write-Host "Found w32-pthreads-config.cmake at: $ConfigFile"
            break
        }
    }
    
    # If we still can't find w32-pthreads, try looking more broadly
    if (-not $W32PthreadsPath) {
        Write-Host "Searching for w32-pthreads config files in all dependencies directories..."
        $W32Files = Get-ChildItem -Path $ProjectRoot -Recurse -Filter "w32-pthreads*Config.cmake" -ErrorAction SilentlyContinue
        foreach ($File in $W32Files) {
            Write-Host "  Found w32-pthreads config at: $($File.FullName)"
            $W32PthreadsPath = $File.Directory.FullName
        }
    }
    
    # If all else fails, try looking in the vcpkg directory
    if (-not $W32PthreadsPath) {
        Write-Host "Looking for w32-pthreads in vcpkg installed packages..."
        $VcpkgInstalled = Join-Path -Path $ProjectRoot -ChildPath "vcpkg\installed"
        if (Test-Path $VcpkgInstalled) {
            $W32Files = Get-ChildItem -Path $VcpkgInstalled -Recurse -Filter "w32-pthreads*Config.cmake" -ErrorAction SilentlyContinue
            foreach ($File in $W32Files) {
                Write-Host "  Found w32-pthreads config in vcpkg at: $($File.FullName)"
                $W32PthreadsPath = $File.Directory.FullName
            }
        }
    }
    
    # Set these paths based on where we know files exist
    $LibObsPath = $DotDepsConfigPath  # Use .deps/cmake for libobs where we know it was found
    if (-not $W32PthreadsPath) {
        # If we still can't find w32-pthreads, try a fallback approach
        Write-Host "Could not find w32-pthreads config file. Will create a simple one..."
        
        # Create a simple config file for w32-pthreads
        $W32PthreadsPath = Join-Path -Path $BuildDir -ChildPath "w32-pthreads-config"
        if (!(Test-Path $W32PthreadsPath)) {
            New-Item -ItemType Directory -Path $W32PthreadsPath -Force | Out-Null
        }
        
        $ConfigContent = @"
# Auto-generated w32-pthreads config file
set(W32_PTHREADS_INCLUDE_DIRS "${DepsPath}/include")
set(W32_PTHREADS_LIBRARIES "${DepsPath}/lib/w32-pthreads.lib")
add_library(w32-pthreads SHARED IMPORTED)
set_target_properties(w32-pthreads PROPERTIES
    IMPORTED_LOCATION "${DepsPath}/bin/w32-pthreads.dll"
    IMPORTED_IMPLIB "${DepsPath}/lib/w32-pthreads.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${DepsPath}/include"
)
add_library(OBS::w32-pthreads ALIAS w32-pthreads)
"@
        
        $ConfigFilePath = Join-Path -Path $W32PthreadsPath -ChildPath "w32-pthreadsConfig.cmake"
        Set-Content -Path $ConfigFilePath -Value $ConfigContent
        Write-Host "Created w32-pthreadsConfig.cmake at: $ConfigFilePath"
    }
    
    # Ensure vcpkg toolchain path is correct
    $VcpkgRoot = (Resolve-Path "${ProjectRoot}\vcpkg").Path
    $VcpkgToolchain = Join-Path $VcpkgRoot 'scripts\buildsystems\vcpkg.cmake'
    
    # Add binaries to path so that DLLs can be found
    $env:PATH = "$DepsPath\bin;$env:PATH"
    
    # Convert all paths to forward slashes for CMake
    $ProjectRootCMake = $ProjectRoot.ToString().Replace('\', '/')
    $BuildDirCMake = $BuildDir.ToString().Replace('\', '/')
    $DepsPathCMake = $DepsPath.ToString().Replace('\', '/')
    $LibObsPathCMake = $LibObsPath.ToString().Replace('\', '/')
    $FrontendApiPathCMake = $LibObsPath.ToString().Replace('\', '/')
    $W32PthreadsPathCMake = $W32PthreadsPath.ToString().Replace('\', '/')
    $VcpkgToolchainCMake = $VcpkgToolchain.ToString().Replace('\', '/')
    
    Write-Host "Using CMake-style paths:"
    Write-Host "  Project root: $ProjectRootCMake"
    Write-Host "  Build directory: $BuildDirCMake"
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