<#
.SYNOPSIS
    Repo B Cleanup Script (Runtime-Only Mirror, V9.3.5)

.DESCRIPTION
    Fully empties Repo B so it can be repopulated by Sync-Dev.
    This is a true pre-sync cleanup:
      - deletes all files and folders under Repo B
      - recreates only the Repo B root if needed
      - does NOT pre-create scripts/ or wheel/
#>

[CmdletBinding()]
param(
    [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Repo B Cleanup Script (Runtime-Only Mirror) ===" -ForegroundColor Cyan
Write-Host "Repo B root: $RepoB"

if (-not (Test-Path $RepoB)) {
    Write-Host "  [CREATE] Repo B root did not exist. Creating..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $RepoB -Force | Out-Null
    Write-Host ""
    Write-Host "Cleanup Complete. Repo B is now aligned for Build-Suite." -ForegroundColor Green
    exit 0
}

Write-Host "  [DELETE] Removing all existing contents..." -ForegroundColor Yellow

Get-ChildItem -Path $RepoB -Force -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

# Safety check: recreate root if somehow removed externally
if (-not (Test-Path $RepoB)) {
    New-Item -ItemType Directory -Path $RepoB -Force | Out-Null
}

# Verify truly empty
$remaining = @(Get-ChildItem -Path $RepoB -Force -ErrorAction SilentlyContinue)
if ($remaining.Count -gt 0) {
    Write-Host "[FAIL] Repo B cleanup incomplete. Remaining items detected:" -ForegroundColor Red
    foreach ($item in $remaining) {
        Write-Host "  - $($item.Name)" -ForegroundColor Red
    }
    exit 2
}

Write-Host ""
Write-Host "Cleanup Complete. Repo B is now aligned for Build-Suite." -ForegroundColor Green
exit 0
