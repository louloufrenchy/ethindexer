# Rollback-Single.ps1
# Rolls back a single host using deployment_manifest.json

param(
    [Parameter(Mandatory = $true)]
    [string]$Host
)

Import-Module "$PSScriptRoot\Deploy-ForensicSuite.psm1" -Force

# Load manifest
$manifestPath = Join-Path $PSScriptRoot "deployment_manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Host "ERROR: deployment_manifest.json not found at $manifestPath" -ForegroundColor Red
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

# Find host entry
$target = $manifest.hosts | Where-Object { $_.ip -eq $Host }

if (-not $target) {
    Write-Host "ERROR: Host $Host not found in manifest." -ForegroundColor Red
    exit 1
}

Write-Host "=== ROLLBACK: $Host ===" -ForegroundColor Yellow

Uninstall-ForensicSuite -Host $Host | Out-Null
Cleanup-RemoteInstaller -Host $Host | Out-Null

Write-Host "=== Rollback complete for $Host ===" -ForegroundColor Green
