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
    
    # Set paths for libobs and obs-frontend-api
    $LibObsPath = $DotDepsConfigPath
    $FrontendApiPath = $DotDepsConfigPath
    
    # Ensure vcpkg toolchain path is correct
    $VcpkgRoot = (Resolve-Path "${ProjectRoot}\vcpkg").Path
    $VcpkgToolchain = Join-Path $VcpkgRoot 'scripts\buildsystems\vcpkg.cmake'
    
    # Add binaries to path so that DLLs can be found
    $env:PATH = "$DepsPath\bin;$env:PATH"
    
    # Convert all paths to forward slashes for CMake
    $ProjectRootCMake = $ProjectRoot.Replace('\', '/')
    $BuildDirCMake = $BuildDir.Replace('\', '/')
    $DepsPathCMake = $DepsPath.Replace('\', '/')
    $LibObsPathCMake = $LibObsPath.Replace('\', '/')
    $FrontendApiPathCMake = $FrontendApiPath.Replace('\', '/')
    $VcpkgToolchainCMake = $VcpkgToolchain.Replace('\', '/')
    
    Write-Host "Using CMake-style paths:"
    Write-Host "  Dependencies: $DepsPathCMake"
    Write-Host "  libobs: $LibObsPathCMake"
    Write-Host "  frontend-api: $FrontendApiPathCMake"
    Write-Host "  Vcpkg toolchain: $VcpkgToolchainCMake"
    
    # For w32-pthreads, instead of creating a config file, we'll pass the include and lib directories directly
    Write-Host "Checking for w32-pthreads in $DepsPath..."
    $W32PthreadsInclude = Join-Path -Path $DepsPath -ChildPath "include"
    $W32PthreadsLib = Join-Path -Path $DepsPath -ChildPath "lib\w32-pthreads.lib"
    
    if (!(Test-Path $W32PthreadsLib)) {
        Write-Host "Could not find w32-pthreads.lib in $W32PthreadsLib"
        $W32PthreadsLibSearch = Get-ChildItem -Path $DepsPath -Recurse -Filter "w32-pthreads.lib" -ErrorAction SilentlyContinue
        if ($W32PthreadsLibSearch) {
            $W32PthreadsLib = $W32PthreadsLibSearch[0].FullName
            Write-Host "Found w32-pthreads.lib at: $W32PthreadsLib"
        }
    }
    
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
        "-DOBS_WEBRTC_ENABLED=OFF"
    )
    
    # Modify the CMakeLists.txt to avoid attempting to find w32-pthreads package
    Write-Host "Modifying CMakeLists.txt to avoid w32-pthreads package finding..."
    $CmakeListsPath = Join-Path -Path $ProjectRoot -ChildPath "CMakeLists.txt"
    $CmakeListsContent = Get-Content -Path $CmakeListsPath -Raw
    
    # Check if already modified
    if ($CmakeListsContent -notmatch "# Modified for w32-pthreads") {
        # Look for the find_package(w32-pthreads REQUIRED CONFIG) line
        $ModifiedContent = $CmakeListsContent -replace "find_package\(w32-pthreads REQUIRED CONFIG\)", "# Modified for w32-pthreads: Skipping find_package for w32-pthreads"
        
        # Add direct link to w32-pthreads instead of using find_package
        $ModifiedContent = $ModifiedContent -replace "target_link_libraries\(\$\{CMAKE_PROJECT_NAME\} PRIVATE OBS::w32-pthreads\)", "# Use direct path to w32-pthreads library`ntarget_include_directories(`${CMAKE_PROJECT_NAME} PRIVATE `"$($W32PthreadsInclude.Replace('\', '/'))`")`ntarget_link_libraries(`${CMAKE_PROJECT_NAME} PRIVATE `"$($W32PthreadsLib.Replace('\', '/'))`")"
        
        # Write the modified content back to the file
        Set-Content -Path $CmakeListsPath -Value $ModifiedContent
        Write-Host "CMakeLists.txt modified successfully."
    } else {
        Write-Host "CMakeLists.txt already modified."
    }
    
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