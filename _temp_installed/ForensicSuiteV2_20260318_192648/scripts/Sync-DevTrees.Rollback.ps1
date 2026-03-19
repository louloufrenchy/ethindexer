param(
    [string]$RepoB_Root = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2",
    [string]$BackupRoot = "F:\tools\RepoB_Backups"
)

Write-Host "=== Sync-DevTrees ROLLBACK (Runtime-Only, Wheel-Based) ===" -ForegroundColor Cyan
Write-Host "RepoB root: $RepoB_Root"
Write-Host "Backup root: $BackupRoot"
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

Write-Host "`nYou selected backup: $($selectedBackup.Name)" -ForegroundColor Cyan
$confirm = Read-Host "Restore this backup? This will overwrite RepoB. (y/N)"

if ($confirm -ne "y") {
    Write-Host "Rollback aborted." -ForegroundColor Red
    return
}

Write-Host "`n[ROLLBACK] Removing current RepoB..." -ForegroundColor Yellow
if (Test-Path $RepoB_Root) {
    Remove-Item -LiteralPath $RepoB_Root -Recurse -Force
}

Write-Host "[ROLLBACK] Restoring RepoB from backup..." -ForegroundColor Yellow
Copy-Item -LiteralPath $selectedBackup.FullName -Destination $RepoB_Root -Recurse -Force

Write-Host "`n[SUCCESS] RepoB restored from backup: $($selectedBackup.Name)" -ForegroundColor Green
Write-Host "Run Sync-DevTrees.Validate.ps1 to confirm integrity."
