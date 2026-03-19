# =====================================================================
# FILE: scripts\forensic_suite_RepoB_cleanup.ps1
# =====================================================================
# Repo B Cleanup (V9.3)
# Runtime-only hygiene for F:\DEVELOPMENT\Repo_B\forensic_suite_v2
# =====================================================================

param(
    [string]$RepoB_Root = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

Write-Host "=== Repo B Cleanup Script (Runtime-Only Mirror) ===" -ForegroundColor Cyan
Write-Host "Repo B root: $RepoB_Root" -ForegroundColor Gray

if (!(Test-Path $RepoB_Root)) {
    Write-Host "forensic_suite_v2_RepoB_cleanup.ps1: Repo B path not found: $RepoB_Root" -ForegroundColor Yellow
    exit 0
}

$allowed = @(
    "forensic_suite_v2",
    "grafana",
    "indexers",
    "pyproject.toml",
    "requirements.txt"
)

$items = Get-ChildItem -LiteralPath $RepoB_Root

foreach ($item in $items) {
    $name = $item.Name
    if ($allowed -contains $name) {
        Write-Host "  [KEEP] Verified Runtime Component: $name" -ForegroundColor Green
    } else {
        Write-Host "  [DELETE] Removing unexpected top-level item: $name" -ForegroundColor Magenta
        if ($item.PSIsContainer) {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        } else {
            Remove-Item -LiteralPath $item.FullName -Force
        }
    }
}

Write-Host "`nCleanup Complete. Repo B is now aligned for Build-Suite." -ForegroundColor Green
exit 0
