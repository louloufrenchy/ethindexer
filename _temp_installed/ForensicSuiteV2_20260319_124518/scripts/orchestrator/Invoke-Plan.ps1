# Invoke-Plan.ps1
# Requires -Version 7.0

param(
    [switch]$Deploy,
    [switch]$DryRun,
    [switch]$CheckPackage
)

Write-Host "=== DEPLOY: SSH/SCP orchestrator ===" -ForegroundColor Cyan

Import-Module "$PSScriptRoot\Orchestrator.psm1" -Force

if ($DryRun) {
    Set-DryRun -Enabled
    Write-Host "=== DRY RUN MODE ===" -ForegroundColor Yellow
}

if ($CheckPackage) {
    Write-Host "=== PACKAGE HEALTH CHECK ===" -ForegroundColor Cyan
    Invoke-Parallel -ActionName "Test-ForensicSuiteHealth" -StepName "HealthCheck" | Out-Null
    Write-Host "=== Health check complete ===" -ForegroundColor Green
    return
}

# Normal deploy path
if (-not (Invoke-Step `
    -Name "EnsureTemp" `
    -ActionName "Ensure-RemoteTemp" `
    -RollbackActionName $null)) { return }

if (-not (Invoke-Step `
    -Name "UploadInstaller" `
    -ActionName "Upload-Installer" `
    -RollbackActionName "Cleanup-Installer")) { return }

if (-not (Invoke-Step `
    -Name "UninstallOld" `
    -ActionName "Uninstall-ForensicSuite" `
    -RollbackActionName $null)) { return }

if (-not (Invoke-Step `
    -Name "InstallNew" `
    -ActionName "Install-ForensicSuite" `
    -RollbackActionName "Uninstall-ForensicSuite")) { return }

if (-not (Invoke-Step `
    -Name "CleanupInstaller" `
    -ActionName "Cleanup-Installer" `
    -RollbackActionName $null)) { return }

if (-not (Invoke-Step `
    -Name "HealthCheck" `
    -ActionName "Test-ForensicSuiteHealth" `
    -RollbackActionName $null)) { return }

Write-Host "=== Deployment complete ===" -ForegroundColor Green