# Rollback-All.ps1
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
