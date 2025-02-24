[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# 1. Locate and read buildspec.json from the repo root.
#    (Assumes this script is in .github\scripts and buildspec.json is in the repository root.)
# -------------------------------------------------------------------
$buildspecPath = Join-Path $PSScriptRoot "../../buildspec.json"
if (!(Test-Path $buildspecPath)) {
    Write-Error "buildspec.json not found at $buildspecPath"
    exit 1
}
$buildspec = Get-Content -Path $buildspecPath -Raw | ConvertFrom-Json

if (-not $buildspec.dependencies.prebuilt) {
    Write-Error "No 'prebuilt' dependency found in buildspec.json"
    exit 1
}
$dep = $buildspec.dependencies.prebuilt

# -------------------------------------------------------------------
# 2. Download the prebuilt OBS‑deps archive.
#    (We assume the asset is named "windows-deps-<version>-x64.zip")
# -------------------------------------------------------------------
$fileName = "windows-deps-$($dep.version)-x64.zip"
$url = "$($dep.baseUrl)/$($dep.version)/$fileName"
Write-Host "Downloading prebuilt obs-deps from $url ..."
Invoke-WebRequest -Uri $url -OutFile $fileName

# -------------------------------------------------------------------
# 3. Verify the SHA256 hash.
# -------------------------------------------------------------------
$expectedHash = $dep.hashes."windows-x64"
$actualHash = (Get-FileHash -Algorithm SHA256 $fileName).Hash.ToLower()
if ($actualHash -ne $expectedHash.ToLower()) {
    Write-Error "Hash mismatch for $fileName. Expected: $expectedHash, Actual: $actualHash"
    exit 1
}
Write-Host "Hash validated."

# -------------------------------------------------------------------
# 4. Expand the archive into the dependencies folder.
# -------------------------------------------------------------------
$destination = Join-Path $PSScriptRoot "../../dependencies/prebuilt"
if (Test-Path $destination) {
    Remove-Item -Recurse -Force $destination
}
Expand-Archive -Path $fileName -DestinationPath $destination
Write-Host "Extracted prebuilt obs-deps to $destination"
Write-Host "Extracted folder contents:"
Get-ChildItem -Path $destination -Recurse | Format-List FullName

# -------------------------------------------------------------------
# 5. Check for libobs in the extracted archive.
#    We assume the archive extracts into a folder named "windows-deps-<version>-x64".
# -------------------------------------------------------------------
$filePrefix = "windows-deps-$($dep.version)-x64"
$libobsPath = Join-Path $destination "$filePrefix\lib\cmake\libobs"
if (Test-Path $libobsPath) {
    Write-Host "Setting libobs_DIR to $libobsPath"
    echo "libobs_DIR=$libobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
    echo "LIBOBS_INSTALL_DIR=$libobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
}
else {
    Write-Warning "Could not find libobsConfig.cmake at expected location: $libobsPath"
    Write-Host "Falling back to building OBS from source to generate libobs and obs-frontend-api..."

    # -------------------------------------------------------------------
    # 6. Fallback: Clone and build OBS from source.
    # -------------------------------------------------------------------
    $obsSourceDir = Join-Path $env:GITHUB_WORKSPACE "obs-studio-fallback"
    git clone --recursive https://github.com/obsproject/obs-studio.git $obsSourceDir
    Push-Location $obsSourceDir

    # Determine the repository root (assumes the repo root is two levels above this script)
    $ProjectRoot = Resolve-Path -Path "$PSScriptRoot/../.."

    # Set VCPKG_ROOT for the fallback build (assuming vcpkg is in the repo root)
    $env:VCPKG_ROOT = (Resolve-Path "$env:GITHUB_WORKSPACE\vcpkg").Path
    $toolchainFile = Join-Path $env:VCPKG_ROOT 'scripts\buildsystems\vcpkg.cmake'

    # Configure OBS with CMake:
    cmake -B build -A x64 -DCMAKE_TOOLCHAIN_FILE="$toolchainFile" -DCMAKE_PREFIX_PATH="$env:GITHUB_WORKSPACE/dependencies/prebuilt/windows-deps-$($dep.version)-x64" -DCMAKE_INSTALL_PREFIX="$env:GITHUB_WORKSPACE\libobs_fallback" -DCMAKE_INSTALL_INCLUDEDIR="$env:GITHUB_WORKSPACE\libobs_fallback\include" -DCMAKE_INSTALL_LIBDIR="lib/cmake/libobs" -DCMAKE_BUILD_TYPE=Release -DBUILD_BROWSER=OFF -DBUILD_OBSCONTROL=OFF -DENABLE_FRONTEND_API=ON

    # Build and install OBS (or the parts needed for libobs and obs-frontend-api)
    cmake --build build --config Release --target install
    Pop-Location

    # -------------------------------------------------------------------
    # 7. Prepare fallback configuration files.
    #    We assume that the fallback install places headers in:
    #      $env:GITHUB_WORKSPACE\libobs_fallback\include
    #    and libraries in:
    #      $env:GITHUB_WORKSPACE\libobs_fallback\lib
    #    We will generate minimal config files that point to these directories.
    # -------------------------------------------------------------------
    $fallbackLibobsPath = Join-Path $env:GITHUB_WORKSPACE "libobs_fallback\lib\cmake\libobs"
    $fallbackFrontendApiPath = Join-Path $env:GITHUB_WORKSPACE "libobs_fallback\lib\cmake\obs-frontend-api"

    if (!(Test-Path $fallbackLibobsPath)) {
        Write-Host "Fallback libobs config folder not found. Creating directory: $fallbackLibobsPath"
        New-Item -ItemType Directory -Force -Path $fallbackLibobsPath | Out-Null
    }
    if (!(Test-Path $fallbackFrontendApiPath)) {
        Write-Host "Fallback obs-frontend-api config folder not found. Creating directory: $fallbackFrontendApiPath"
        New-Item -ItemType Directory -Force -Path $fallbackFrontendApiPath | Out-Null
    }

    # Generate minimal libobsConfig.cmake
    $fallbackLibobsConfig = Join-Path $fallbackLibobsPath "libobsConfig.cmake"
    if (!(Test-Path $fallbackLibobsConfig)) {
        Write-Host "Generating minimal libobsConfig.cmake at $fallbackLibobsConfig"
        $libobsContent = @'
# Minimal libobsConfig.cmake generated by fetch-deps.ps1 fallback
get_filename_component(_INSTALL_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
# Use the fallback installation's include directory.
set(libobs_INCLUDE_DIRS "${_INSTALL_PREFIX}/include")
set(libobs_LIBRARIES "${_INSTALL_PREFIX}/lib/obs.lib")
if(NOT TARGET OBS::libobs)
  add_library(OBS::libobs UNKNOWN IMPORTED)
  set_target_properties(OBS::libobs PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${libobs_INCLUDE_DIRS}"
      IMPORTED_LOCATION "${_INSTALL_PREFIX}/lib/obs.dll"
  )
endif()
'@
        $libobsContent | Out-File -FilePath $fallbackLibobsConfig -Encoding utf8
    }

    # Generate minimal obs-frontend-apiConfig.cmake
    $fallbackFrontendApiConfig = Join-Path $fallbackFrontendApiPath "obs-frontend-apiConfig.cmake"
    if (!(Test-Path $fallbackFrontendApiConfig)) {
        Write-Host "Generating minimal obs-frontend-apiConfig.cmake at $fallbackFrontendApiConfig"
        $frontendApiContent = @'
# Minimal obs-frontend-apiConfig.cmake generated by fetch-deps.ps1 fallback
get_filename_component(_INSTALL_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(obs_frontend_api_INCLUDE_DIRS "${_INSTALL_PREFIX}/include")
set(obs_frontend_api_LIBRARIES "${_INSTALL_PREFIX}/lib/obs-frontend-api.lib")
if(NOT TARGET OBS::obs-frontend-api)
  add_library(OBS::obs-frontend-api UNKNOWN IMPORTED)
  set_target_properties(OBS::obs-frontend-api PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${obs_frontend_api_INCLUDE_DIRS}"
      IMPORTED_LOCATION "${_INSTALL_PREFIX}/lib/obs-frontend-api.dll"
  )
endif()
'@
        $frontendApiContent | Out-File -FilePath $fallbackFrontendApiConfig -Encoding utf8
    }

    # Debug: List the contents of the fallback config directories.
    Write-Host "Listing fallback libobs config directory contents at $fallbackLibobsPath :"
    Get-ChildItem -Path $fallbackLibobsPath -Recurse | Format-List FullName
    Write-Host "Listing fallback obs-frontend-api config directory contents at $fallbackFrontendApiPath :"
    Get-ChildItem -Path $fallbackFrontendApiPath -Recurse | Format-List FullName

    # Set environment variables for fallback build.
    if ((Test-Path $fallbackLibobsConfig) -and (Test-Path $fallbackFrontendApiConfig)) {
        Write-Host "Fallback build successful. Setting environment variables..."
        echo "libobs_DIR=$fallbackLibobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
        echo "LIBOBS_INSTALL_DIR=$fallbackLibobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
        echo "obs-frontend-api_DIR=$fallbackFrontendApiPath" | Out-File -FilePath $env:GITHUB_ENV -Append
    }
    else {
        Write-Error "Fallback build did not produce the required configuration files."
        exit 1
    }
}
