[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Define the path to buildspec.json relative to this script.
# (Assumes this script is in .github/scripts and buildspec.json is in the repo root.)
$buildspecPath = Join-Path $PSScriptRoot "../../buildspec.json"
if (!(Test-Path $buildspecPath)) {
    Write-Error "buildspec.json not found at $buildspecPath"
    exit 1
}

# Read and parse buildspec.json.
$buildspec = Get-Content -Path $buildspecPath -Raw | ConvertFrom-Json

# We want to use the 'prebuilt' dependency (which should contain libobs among other things).
if (-not $buildspec.dependencies.prebuilt) {
    Write-Error "No 'prebuilt' dependency found in buildspec.json"
    exit 1
}

$dep = $buildspec.dependencies.prebuilt

# Construct the file name and URL for Windows x64.
# We assume the asset is named "windows-deps-<version>-x64.zip"
$fileName = "windows-deps-$($dep.version)-x64.zip"
$url = "$($dep.baseUrl)/$($dep.version)/$fileName"

Write-Host "Downloading prebuilt obs-deps from $url ..."
Invoke-WebRequest -Uri $url -OutFile $fileName

# Verify the SHA256 hash (for Windows-x64)
$expectedHash = $dep.hashes."windows-x64"
$actualHash = (Get-FileHash -Algorithm SHA256 $fileName).Hash.ToLower()

if ($actualHash -ne $expectedHash.ToLower()) {
    Write-Error "Hash mismatch for $fileName. Expected: $expectedHash, Actual: $actualHash"
    exit 1
}

Write-Host "Hash validated."

# Define the destination folder where the archive will be extracted.
$destination = Join-Path $PSScriptRoot "../../dependencies/prebuilt"
if (Test-Path $destination) {
    Remove-Item -Recurse -Force $destination
}
Expand-Archive -Path $fileName -DestinationPath $destination

Write-Host "Extracted prebuilt obs-deps to $destination"
Write-Host "Extracted folder contents:"
Get-ChildItem -Path $destination -Recurse | Format-List FullName

# Determine the expected folder for libobs.
# This script assumes the archive extracts into a folder named "windows-deps-<version>-x64"
$filePrefix = "windows-deps-$($dep.version)-x64"
$libobsPath = Join-Path $destination "$filePrefix\lib\cmake\libobs"

if (Test-Path $libobsPath) {
    Write-Host "Setting libobs_DIR to $libobsPath"
    echo "libobs_DIR=$libobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
    echo "LIBOBS_INSTALL_DIR=$libobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
} else {
    Write-Warning "Could not find libobsConfig.cmake at expected location: $libobsPath"
    Write-Host "Falling back to building OBS from source to generate libobs..."

    # Define a folder for the fallback OBS build.
    $obsSourceDir = Join-Path $env:GITHUB_WORKSPACE "obs-studio-fallback"

    # Clone the OBS Studio repository into the fallback folder.
    git clone --recursive https://github.com/obsproject/obs-studio.git $obsSourceDir

    Push-Location $obsSourceDir

    # Run CMake to configure the build.
    # We add the flag -DCMAKE_INSTALL_LIBDIR="lib/cmake/libobs" to force installation
    # of libobs config files into the expected subfolder.
    cmake -B build -A x64 -DCMAKE_INSTALL_PREFIX="$env:GITHUB_WORKSPACE\libobs_fallback" -DCMAKE_INSTALL_LIBDIR="lib/cmake/libobs" -DCMAKE_BUILD_TYPE=Release -DBUILD_BROWSER=OFF -DBUILD_OBSCONTROL=OFF

    # Build and install OBS Studio (or at least libobs) from the fallback source.
    cmake --build build --config Release --target install
    Pop-Location

    # Set the fallback libobs path.
    $fallbackLibobsPath = Join-Path $env:GITHUB_WORKSPACE "libobs_fallback\lib\cmake\libobs"
    if (Test-Path $fallbackLibobsPath) {
        Write-Host "Fallback build successful. Setting libobs_DIR to $fallbackLibobsPath"
        echo "libobs_DIR=$fallbackLibobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
        echo "LIBOBS_INSTALL_DIR=$fallbackLibobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
    } else {
        Write-Error "Fallback build of libobs did not produce libobsConfig.cmake at expected location: $fallbackLibobsPath"
        exit 1
    }

}