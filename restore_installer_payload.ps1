param(
    [string]$ProjectRoot      = "C:\development\forensic_tracer_installer_project_root",
    [string]$PayloadPath      = "C:\development\forensic_tracer_installer_project_root\installer_payload",
    [string]$BuildSuitePath   = "C:\development\forensic_tracer_installer_project_root\build\ForensicSuite",
    [string]$RepoRootForensic = "C:\development\forensic_suite_v2",
    [string]$DistPath         = "C:\development\forensic_tracer_installer_project_root\dist",
    [string]$TronDbPath       = "C:\development\tron_indexer\db",
    [string]$TronSqlPath      = "C:\development\forensic_suite_v2\forensic_suite_v2\tron_indexer\sql"
)

Write-Host "=== RESTORING INSTALLER PAYLOAD (v4 FINAL) ===" -ForegroundColor Cyan

# 1. Validate core paths
if (-not (Test-Path $BuildSuitePath)) {
    Write-Error "ERROR: Runtime suite not found at $BuildSuitePath"
    exit 1
}

if (-not (Test-Path $PayloadPath)) {
    New-Item -ItemType Directory -Path $PayloadPath | Out-Null
}

# 2. Wipe existing payload
Write-Host "Cleaning existing payload..." -ForegroundColor Yellow
Get-ChildItem -Path $PayloadPath -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Payload cleared." -ForegroundColor Green

# 3. Recreate folder structure
$folders = @(
    "ForensicSuite",
    "config",
    "dashboards",
    "db",
    "scripts",
    "tools"
)

foreach ($folder in $folders) {
    New-Item -ItemType Directory -Path (Join-Path $PayloadPath $folder) -Force | Out-Null
}
Write-Host "Folder structure recreated." -ForegroundColor Green

# 4. Copy frozen suite
Write-Host "Copying frozen ForensicSuite runtime..." -ForegroundColor Yellow
Copy-Item -Recurse -Force `
    -Path "$BuildSuitePath\*" `
    -Destination "$PayloadPath\ForensicSuite"
Write-Host "Frozen suite copied." -ForegroundColor Green

# 5. Copy config
$configSource = Join-Path $RepoRootForensic "forensic_suite_v2\config"
Copy-Item -Recurse -Force "$configSource\*" "$PayloadPath\config"

# 6. Copy dashboards
$dashSource = Join-Path $RepoRootForensic "forensic_suite_v2\dashboards"
Copy-Item -Recurse -Force "$dashSource\*" "$PayloadPath\dashboards"

# 7. Copy DB schema (TRON)
if (Test-Path $TronDbPath) {
    Write-Host "Copying TRON DB schema from $TronDbPath..." -ForegroundColor Yellow
    Copy-Item -Recurse -Force "$TronDbPath\*" "$PayloadPath\db"
}

# 8. Copy TRON dashboard SQL
if (Test-Path $TronSqlPath) {
    Write-Host "Copying TRON SQL files from $TronSqlPath..." -ForegroundColor Yellow
    Copy-Item -Recurse -Force "$TronSqlPath\*" "$PayloadPath\db"
}

# 9. Copy scripts
Copy-Item -Recurse -Force "$ProjectRoot\scripts\*" "$PayloadPath\scripts"

# 10. Copy tools (from backup)
$toolsSource = "$ProjectRoot\backup_forensic_suite_v2_20260219_175638\tools"
if (Test-Path $toolsSource) {
    Copy-Item -Recurse -Force "$toolsSource\*" "$PayloadPath\tools"
}

# 11. Copy wheel
Copy-Item -Force "$DistPath\forensic_suite_v2-0.1.2-py3-none-any.whl" $PayloadPath

# 12. Copy Python installer
Copy-Item -Force "C:\Program Files\ForensicSuiteV2\python-3.14.2-amd64.exe" $PayloadPath

# 13. Copy Cytoscape installer
Copy-Item -Force "C:\Program Files\ForensicSuiteV2\Cytoscape_3_10_4_windows_64bit.exe" $PayloadPath

# 14. Copy bootstrap.ps1
Copy-Item -Force "$ProjectRoot\bootstrap.ps1" $PayloadPath

Write-Host "=== PAYLOAD RESTORE v4 COMPLETE — FULLY REBUILT ===" -ForegroundColor Cyan

