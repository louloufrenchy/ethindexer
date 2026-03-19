# Requires -Version 7.0
# Rollback.ps1

Import-Module "$PSScriptRoot\Orchestrator.psm1" -Force

Write-Host "=== ROLLBACK: Forensic Suite ===" -ForegroundColor Yellow

Invoke-Step -Name "Rollback-Uninstall" -Action {
    param($TargetHost)
    Uninstall-ForensicSuite -TargetHost $TargetHost
} -Rollback {
    param($TargetHost)
    # No rollback for rollback
} | Out-Null

Invoke-Step -Name "Rollback-Cleanup" -Action {
    param($TargetHost)
    Cleanup-Installer -TargetHost $TargetHost
} -Rollback {
    param($TargetHost)
    # No rollback
} | Out-Null

Write-Host "=== Rollback complete ===" -ForegroundColor Green