function Invoke-ForensicDeployment {
    param(
        [switch]$DryRun
    )

    Write-Host ""
    Write-Host "=== ForensicSuiteV2 Deployment ===" -ForegroundColor Cyan

    if (-not (Invoke-Step -Name "EnsureTemp" -ActionName "Ensure-RemoteTemp" -RollbackActionName $null)) { return }
    if (-not (Invoke-Step -Name "UploadInstaller" -ActionName "Upload-Installer" -RollbackActionName $null)) { return }
    if (-not (Invoke-Step -Name "UninstallOld" -ActionName "Uninstall-ForensicSuite" -RollbackActionName $null)) { return }
    if (-not (Invoke-Step -Name "InstallNew" -ActionName "Install-ForensicSuite" -RollbackActionName $null)) { return }
    if (-not (Invoke-Step -Name "CleanupInstaller" -ActionName "Cleanup-Installer" -RollbackActionName $null)) { return }

    Write-Host ""
    Write-Host "=== Deployment complete ===" -ForegroundColor Green
}
