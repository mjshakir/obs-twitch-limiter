[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Define the path to buildspec.json relative to this script
$buildspecPath = Join-Path $PSScriptRoot "../../buildspec.json"
if (!(Test-Path $buildspecPath)) {
    Write-Error "buildspec.json not found at $buildspecPath"
    exit 1
}

# Read and parse buildspec.json
$buildspec = Get-Content -Path $buildspecPath -Raw | ConvertFrom-Json

# We want to use the 'prebuilt' dependency, which should contain libobs among other things.
if (-not $buildspec.dependencies.prebuilt) {
    Write-Error "No 'prebuilt' dependency found in buildspec.json"
    exit 1
}

$dep = $buildspec.dependencies.prebuilt

# Construct the file name and URL for Windows x64.
# This example assumes the file is named "<version>-windows-x64.zip"
$fileName = "$($dep.version)-windows-x64.zip"
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
# For example, we extract into a "dependencies" folder at the repository root.
$destination = Join-Path $PSScriptRoot "../dependencies/prebuilt"
if (Test-Path $destination) {
    Remove-Item -Recurse -Force $destination
}
Expand-Archive -Path $fileName -DestinationPath $destination

Write-Host "Extracted prebuilt obs-deps to $destination"

# Optionally, if you know that the extracted folder contains libobs at a specific location,
# set an environment variable so that CMake can find it.
# For example, if the archive extracts so that libobs is found at:
#   <destination>\libobs\lib\cmake\libobs
$libobsPath = Join-Path $destination "libobs\lib\cmake\libobs"
if (Test-Path $libobsPath) {
    Write-Host "Setting libobs_DIR to $libobsPath"
    echo "libobs_DIR=$libobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append
} else {
    Write-Warning "Could not find libobsConfig.cmake at expected location: $libobsPath"
}
