# Rollback-Cluster.ps1
# Rolls back hosts by role using deployment_manifest.json

param(
    [string[]]$Roles
)

Import-Module "$PSScriptRoot\Deploy-ForensicSuite.psm1" -Force

# Load manifest
$manifestPath = Join-Path $PSScriptRoot "deployment_manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Host "ERROR: deployment_manifest.json not found at $manifestPath" -ForegroundColor Red
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

# Determine target hosts
if ($Roles -and $Roles.Count -gt 0) {
    Write-Host "Filtering hosts by roles: $($Roles -join ', ')" -ForegroundColor Cyan
    $targets = $manifest.hosts | Where-Object {
        $_.roles | Where-Object { $Roles -contains $_ }
    }
} else {
    Write-Host "No roles specified — rolling back ALL hosts." -ForegroundColor Yellow
    $targets = $manifest.hosts
}

if (-not $targets) {
    Write-Host "No hosts match the specified roles." -ForegroundColor Red
    exit 1
}

Write-Host "=== ROLLBACK: Cluster ===" -ForegroundColor Yellow

foreach ($h in $targets) {
    $ip = $h.ip
    Write-Host "Rollback on $ip (roles: $($h.roles -join ', '))" -ForegroundColor Yellow

    Uninstall-ForensicSuite -Host $ip | Out-Null
    Cleanup-RemoteInstaller -Host $ip | Out-Null
}

Write-Host "=== Cluster rollback complete ===" -ForegroundColor Green
