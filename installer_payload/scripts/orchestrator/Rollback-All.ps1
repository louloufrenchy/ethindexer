# Rollback-All.ps1
<<<<<<< HEAD
# Uses deployment_manifest.json instead of hard-coded host list

Import-Module "$PSScriptRoot\Deploy-ForensicSuite.psm1" -Force

# Load manifest
$manifestPath = Join-Path $PSScriptRoot "deployment_manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Host "ERROR: deployment_manifest.json not found at $manifestPath" -ForegroundColor Red
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$hosts = $manifest.hosts

Write-Host "=== ROLLBACK: Forensic Suite (Manifest-Driven) ===" -ForegroundColor Yellow

foreach ($h in $hosts) {
    $ip = $h.ip
    Write-Host "Rollback on $ip" -ForegroundColor Yellow

    # Uninstall suite
    Uninstall-ForensicSuite -Host $ip | Out-Null

    # Cleanup installer file
    Cleanup-RemoteInstaller -Host $ip | Out-Null
}

Write-Host "=== Rollback complete ===" -ForegroundColor Green
=======
Import-Module "$PSScriptRoot\Deploy-ForensicSuite.psm1" -Force

$Hosts = @(
    "192.168.0.199",
    "192.168.0.165",
    "192.168.0.146"
)

foreach ($h in $Hosts) {
    Write-Host "Rollback on $h" -ForegroundColor Yellow
    Uninstall-ForensicSuite -Host $h | Out-Null
    Cleanup-RemoteInstaller -Host $h | Out-Null
}
>>>>>>> master
