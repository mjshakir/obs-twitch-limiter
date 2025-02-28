[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$buildspecPath = Join-Path $PSScriptRoot "../../buildspec.json"
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

# Download the prebuilt deps
$fileName = "windows-deps-$($dep.version)-x64.zip"
$url = "$($dep.baseUrl)/$($dep.version)/$fileName"
Write-Host "Downloading prebuilt obs-deps from $url ..."
Invoke-WebRequest -Uri $url -OutFile $fileName

# Verify hash
$expectedHash = $dep.hashes."windows-x64"
$actualHash = (Get-FileHash -Algorithm SHA256 $fileName).Hash.ToLower()
if ($actualHash -ne $expectedHash.ToLower()) {
    Write-Error "Hash mismatch for $fileName"
    exit 1
}

# Extract
if (Test-Path $destination) {
    Remove-Item -Recurse -Force $destination
}
Expand-Archive -Path $fileName -DestinationPath $destination

# Set environment variables
$filePrefix = "windows-deps-$($dep.version)-x64"
$libobsPath = Join-Path $destination "$filePrefix\lib\cmake\libobs"
echo "libobs_DIR=$libobsPath" | Out-File -FilePath $env:GITHUB_ENV -Append

$frontendApiPath = Join-Path $destination "$filePrefix\lib\cmake\obs-frontend-api"
echo "obs-frontend-api_DIR=$frontendApiPath" | Out-File -FilePath $env:GITHUB_ENV -Append