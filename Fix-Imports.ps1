# Fix-Imports.ps1
$Root = "C:\development\forensic_tracer_installer_project_root\forensic_suite_v2"

Write-Host "=== Fixing Forensic Suite Imports ===" -ForegroundColor Cyan

# 1. Fix CLI circular import
$cliFile = Join-Path $Root "cli\__main__.py"
if (Test-Path $cliFile) {
    Write-Host "Fixing CLI circular import..."
    $content = Get-Content $cliFile | Where-Object { $_ -notmatch "from forensic_suite_v2.cli.__main__ import cli" }
    Set-Content $cliFile $content
}

# 2. Fix dashboard hardcoded path
$dashFile = Join-Path $Root "btc_indexer\dashboard\btc_dashboard.py"
if (Test-Path $dashFile) {
    Write-Host "Fixing dashboard config path..."
    $content = Get-Content $dashFile

    # Replace entire config-loading block
    $content = $content -replace "open\('C:/forensic_suite_v2/btc_indexer/config/indexer.yaml'\)", "open(Path(__file__).resolve().parents[2] / 'config' / 'indexer.yaml')"

    Set-Content $dashFile $content
}

# 3. Fix db_migrate import
$migrateFile = Join-Path $Root "scripts\db_migrate.py"
if (Test-Path $migrateFile) {
    Write-Host "Fixing db_migrate import..."
    (Get-Content $migrateFile) -replace "from core import", "from forensic_suite_v2.core import" | Set-Content $migrateFile
}

# 4. Fix GUI plugin loader import
$guiFile = Join-Path $Root "gui\app.py"
if (Test-Path $guiFile) {
    Write-Host "Fixing GUI plugin loader import..."
    (Get-Content $guiFile) -replace "from forensic_suite_v2.core.plugin_loader import load_plugins", "from forensic_suite_v2.core.plugin_loader import discover_plugins" | Set-Content $guiFile
}

# 5. Fix missing tracer_engine import in CLI trace
$traceFile = Join-Path $Root "cli\trace.py"
if (Test-Path $traceFile) {
    Write-Host "Fixing trace engine import..."
    (Get-Content $traceFile) -replace "from forensic_suite_v2.tracer_engine", "from forensic_suite_v2.core.tracer_engine" | Set-Content $traceFile
}

Write-Host "=== Import fixes complete ===" -ForegroundColor Green
