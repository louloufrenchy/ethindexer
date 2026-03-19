param(
    [string]$RepoB_Suite = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2\forensic_suite_v2",
    [string]$BackupRoot  = "F:\tools\RepoB_Backups"
)

Write-Host "=== Sync-DevTrees ROLLBACK ===" -ForegroundColor Cyan
Write-Host "RepoB (suite mirror): $RepoB_Suite"
Write-Host "Backup root:          $BackupRoot"
Write-Host ""

if (-not (Test-Path $BackupRoot)) {
    Write-Host "[ERROR] Backup root not found: $BackupRoot" -ForegroundColor Red
    return
}

$backups = Get-ChildItem -Path $BackupRoot -Directory | Sort-Object Name -Descending

if ($backups.Count -eq 0) {
    Write-Host "[ERROR] No backups found in $BackupRoot" -ForegroundColor Red
    return
}

Write-Host "Available backups:" -ForegroundColor Yellow
$index = 1
foreach ($b in $backups) {
    Write-Host "[$index] $($b.Name)"
    $index++
}

$choice = Read-Host "Enter the number of the backup to restore"
if (-not ($choice -as [int]) -or $choice -lt 1 -or $choice -gt $backups.Count) {
    Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
    return
}

$selectedBackup = $backups[$choice - 1]
$backupSuitePath = Join-Path $selectedBackup.FullName "forensic_suite_v2"

if (-not (Test-Path $backupSuitePath)) {
    Write-Host "[ERROR] Backup does not contain a suite folder: $backupSuitePath" -ForegroundColor Red
    return
}

Write-Host "`nYou selected backup: $($selectedBackup.Name)" -ForegroundColor Cyan
$confirm = Read-Host "Restore this backup? This will overwrite RepoB suite. (y/N)"

if ($confirm -ne "y") {
    Write-Host "Rollback aborted." -ForegroundColor Red
    return
}

Write-Host "`n[ROLLBACK] Removing current RepoB suite..." -ForegroundColor Yellow
if (Test-Path $RepoB_Suite) {
    Remove-Item -LiteralPath $RepoB_Suite -Recurse -Force
}

Write-Host "[ROLLBACK] Restoring suite from backup..." -ForegroundColor Yellow
Copy-Item -LiteralPath $backupSuitePath -Destination $RepoB_Suite -Recurse -Force

Write-Host "`n[SUCCESS] RepoB suite restored from backup: $($selectedBackup.Name)" -ForegroundColor Green
Write-Host "Run Sync-DevTrees.Validate.ps1 to confirm integrity."
