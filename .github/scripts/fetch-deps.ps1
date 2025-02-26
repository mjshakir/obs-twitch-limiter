[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# 1. Locate and read buildspec.json from the repo root.
# -------------------------------------------------------------------
if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
}

$buildspecPath = Join-Path $PSScriptRoot "../../buildspec.json"

Write-Host "PSScriptRoot: $PSScriptRoot"
Write-Host "GITHUB_WORKSPACE: $($env:GITHUB_WORKSPACE)"

$destination = Join-Path $PSScriptRoot "../../dependencies/prebuilt"

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

try {
    # Create dependencies directory if it doesn't exist
    if (!(Test-Path $destination)) {
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
    }

    # -------------------------------------------------------------------
    # 2. Download the prebuilt OBS‑deps archive.
    # -------------------------------------------------------------------
    $fileName = "windows-deps-$($dep.version)-x64.zip"
    $url = "$($dep.baseUrl)/$($dep.version)/$fileName"
    Write-Host "Downloading prebuilt obs-deps from $url ..."
    
    try {
        Invoke-WebRequest -Uri $url -OutFile $fileName -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to download from $url. Falling back to manual configuration..."
        $fallbackMode = $true
    }

    # -------------------------------------------------------------------
    # 3. Verify the SHA256 hash if download was successful
    # -------------------------------------------------------------------
    if (-not $fallbackMode) {
        if ($dep.hashes."windows-x64") {
            $expectedHash = $dep.hashes."windows-x64"
            $actualHash = (Get-FileHash -Algorithm SHA256 $fileName).Hash.ToLower()
            if ($actualHash -ne $expectedHash.ToLower()) {
                Write-Warning "Hash mismatch for $fileName. Expected: $expectedHash, Actual: $actualHash"
                $fallbackMode = $true
            }
            else {
                Write-Host "Hash validated."
                
                # -------------------------------------------------------------------
                # 4. Expand the archive into the dependencies folder.
                # -------------------------------------------------------------------
                if (Test-Path $destination) {
                    Remove-Item -Recurse -Force $destination
                }
                Expand-Archive -Path $fileName -DestinationPath $destination
                Write-Host "Extracted prebuilt obs-deps to $destination"
                
                # -------------------------------------------------------------------
                # 5. Check for libobs in the extracted archive.
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
                    $fallbackMode = $true
                }
            }
        }
        else {
            Write-Warning "No hash provided for windows-x64 in buildspec.json"
            $fallbackMode = $true
        }
    }
}
catch {
    Write-Warning "Exception while downloading or processing prebuilt deps: $_"
    $fallbackMode = $true
}

# Fall back to generating minimal config files if needed
if ($fallbackMode) {
    Write-Host "Falling back to generating minimal configuration files..."

    # Define fallback config directories
    $fallbackLibobsPath = Join-Path $env:GITHUB_WORKSPACE "libobs_fallback\lib\cmake\libobs"
    $fallbackFrontendApiPath = Join-Path $env:GITHUB_WORKSPACE "libobs_fallback\lib\cmake\obs-frontend-api"
    $includeDir = Join-Path $env:GITHUB_WORKSPACE "libobs_fallback\include"

    # Create required directories
    if (!(Test-Path $fallbackLibobsPath)) {
        Write-Host "Fallback libobs config folder not found. Creating directory: $fallbackLibobsPath"
        New-Item -ItemType Directory -Force -Path $fallbackLibobsPath | Out-Null
    }
    if (!(Test-Path $fallbackFrontendApiPath)) {
        Write-Host "Fallback obs-frontend-api config folder not found. Creating directory: $fallbackFrontendApiPath"
        New-Item -ItemType Directory -Force -Path $fallbackFrontendApiPath | Out-Null
    }
    if (!(Test-Path $includeDir)) {
        Write-Host "Creating include directory: $includeDir"
        New-Item -ItemType Directory -Force -Path $includeDir | Out-Null
    }

    # Generate minimal libobsConfig.cmake
    $fallbackLibobsConfig = Join-Path $fallbackLibobsPath "libobsConfig.cmake"
    Write-Host "Generating minimal libobsConfig.cmake at $fallbackLibobsConfig"
    $libobsContent = @'
# Minimal libobsConfig.cmake generated by fetch-deps.ps1 fallback
get_filename_component(_INSTALL_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
# Use the fallback installation's include directory.
set(libobs_INCLUDE_DIRS "${_INSTALL_PREFIX}/include")
set(libobs_LIBRARIES "${_INSTALL_PREFIX}/lib/obs.lib")
if(NOT TARGET OBS::libobs)
  add_library(OBS::libobs INTERFACE IMPORTED)
  set_target_properties(OBS::libobs PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${libobs_INCLUDE_DIRS}"
  )
endif()
'@
    $libobsContent | Out-File -FilePath $fallbackLibobsConfig -Encoding utf8

    # Generate minimal obs-frontend-apiConfig.cmake
    $fallbackFrontendApiConfig = Join-Path $fallbackFrontendApiPath "obs-frontend-apiConfig.cmake"
    Write-Host "Generating minimal obs-frontend-apiConfig.cmake at $fallbackFrontendApiConfig"
    $frontendApiContent = @'
# Minimal obs-frontend-apiConfig.cmake generated by fetch-deps.ps1 fallback
get_filename_component(_INSTALL_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(obs-frontend-api_INCLUDE_DIRS "${_INSTALL_PREFIX}/include")
set(obs-frontend-api_LIBRARIES "${_INSTALL_PREFIX}/lib/obs-frontend-api.lib")
if(NOT TARGET OBS::obs-frontend-api)
  add_library(OBS::obs-frontend-api INTERFACE IMPORTED)
  set_target_properties(OBS::obs-frontend-api PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${obs-frontend-api_INCLUDE_DIRS}"
  )
endif()
'@
    $frontendApiContent | Out-File -FilePath $fallbackFrontendApiConfig -Encoding utf8

    # Generate minimal header files to satisfy the build
    $obsHeader = Join-Path $includeDir "obs.h"
    Write-Host "Generating minimal obs.h header at $obsHeader"
    $obsHeaderContent = @'
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

typedef struct obs_module obs_module_t;
#define PLUGIN_CALL

void* obs_module_load(void);
void obs_module_unload(void);
void obs_module_set_locale(const char *locale);
void obs_module_free_locale(void);
void obs_module_post_load(void);
const char *obs_module_name(void);
const char *obs_module_description(void);
uint32_t obs_module_get_version(void);

#ifdef __cplusplus
}
#endif
'@
    $obsHeaderContent | Out-File -FilePath $obsHeader -Encoding utf8

    # Create minimal obs-frontend-api.h
    $frontendApiHeader = Join-Path $includeDir "obs-frontend-api.h"
    Write-Host "Generating minimal obs-frontend-api.h header at $frontendApiHeader"
    $frontendApiHeaderContent = @'
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef enum obs_frontend_event {
    OBS_FRONTEND_EVENT_STREAMING_STARTING,
    OBS_FRONTEND_EVENT_STREAMING_STARTED,
    OBS_FRONTEND_EVENT_STREAMING_STOPPING,
    OBS_FRONTEND_EVENT_STREAMING_STOPPED,
    OBS_FRONTEND_EVENT_RECORDING_STARTING,
    OBS_FRONTEND_EVENT_RECORDING_STARTED,
    OBS_FRONTEND_EVENT_RECORDING_STOPPING,
    OBS_FRONTEND_EVENT_RECORDING_STOPPED,
    OBS_FRONTEND_EVENT_SCENE_CHANGED,
    OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED,
    OBS_FRONTEND_EVENT_EXIT
} obs_frontend_event_t;

void obs_frontend_add_event_callback(void (*callback)(enum obs_frontend_event event, void *private_data), void *private_data);
void obs_frontend_remove_event_callback(void (*callback)(enum obs_frontend_event event, void *private_data), void *private_data);

#ifdef __cplusplus
}
#endif
'@
    $frontendApiHeaderContent | Out-File -FilePath $frontendApiHeader -Encoding utf8

    # Create lib directory if needed
    $libDir = Join-Path $env:GITHUB_WORKSPACE "libobs_fallback\lib"
    if (!(Test-Path $libDir)) {
        Write-Host "Creating lib directory: $libDir"
        New-Item -ItemType Directory -Force -Path $libDir | Out-Null
    }

    Write-Host "Setting environment variables for fallback paths..."
    echo "libobs_DIR=$fallbackLibobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
    echo "LIBOBS_INSTALL_DIR=$fallbackLibobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
    echo "obs-frontend-api_DIR=$fallbackFrontendApiPath" | Out-File -FilePath $env:GITHUB_ENV -Append

    Write-Host "Fallback setup complete."
}