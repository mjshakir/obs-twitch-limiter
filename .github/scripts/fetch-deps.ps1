[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Define the path to buildspec.json relative to this script.
# Assuming this script is in .github/scripts, and buildspec.json is in the repo root.
$buildspecPath = Join-Path $PSScriptRoot "../../buildspec.json"
if (!(Test-Path $buildspecPath)) {
    Write-Error "buildspec.json not found at $buildspecPath"
    exit 1
}

# Read and parse buildspec.json.
$buildspec = Get-Content -Path $buildspecPath -Raw | ConvertFrom-Json

# We want to use the 'prebuilt' dependency, which should contain libobs among other things.
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
# We'll extract into a folder called "dependencies/prebuilt" in the repository root.
$destination = Join-Path $PSScriptRoot "../../dependencies/prebuilt"
if (Test-Path $destination) {
    Remove-Item -Recurse -Force $destination
}
Expand-Archive -Path $fileName -DestinationPath $destination

Write-Host "Extracted prebuilt obs-deps to $destination"

# For debugging, list the extracted folder structure.
Write-Host "Extracted folder contents:"
Get-ChildItem -Path $destination -Recurse | Format-List FullName

# Determine the correct folder for libobs.
# This script assumes the archive extracts into a folder named "windows-deps-<version>-x64"
$filePrefix = "windows-deps-$($dep.version)-x64"
$libobsPath = Join-Path $destination "$filePrefix\lib\cmake\libobs"

if (Test-Path $libobsPath) {
    Write-Host "Setting libobs_DIR to $libobsPath"
    echo "libobs_DIR=$libobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
    echo "LIBOBS_INSTALL_DIR=$libobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
} else {
    Write-Warning "Could not find libobsConfig.cmake at expected location: $libobsPath"
}