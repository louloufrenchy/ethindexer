<#
    bootstrap_dev.ps1
    ------------------
    Development-only bootstrap for Repo A.

    Responsibilities:
      - Activate the Repo A venv
      - Set PYTHONPATH to Repo A root
      - Set DASHBOARD_CONFIG_PATH to Repo A config
      - Validate repo layout (lightweight)
      - Offer launch options for cockpit / CLI / web
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

Write-Host "=== Forensic Suite v2 - Dev Bootstrap ===" -ForegroundColor Cyan
Write-Host "Repo root: $RepoRoot"

$venvActivate = Join-Path $RepoRoot ".venv\Scripts\Activate.ps1"
if (-not (Test-Path $venvActivate)) {
    Write-Host "ERROR: venv not found at $venvActivate" -ForegroundColor Red
    Write-Host "Create it with: python -m venv .venv"
    exit 1
}

Write-Host "Activating venv..."
. $venvActivate

$env:PYTHONPATH = $RepoRoot
$env:DASHBOARD_CONFIG_PATH = Join-Path $RepoRoot "forensic_suite_v2\config\indexer.yaml"

Write-Host "PYTHONPATH set to: $env:PYTHONPATH"
Write-Host "DASHBOARD_CONFIG_PATH set to: $env:DASHBOARD_CONFIG_PATH"

$issues = @()

function Check-Path {
    param(
        [Parameter(Mandatory = $true)][string]$PathToCheck,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path $PathToCheck)) {
        $script:issues += ("Missing {0}: {1}" -f $Label, $PathToCheck)
    }
}

Check-Path -PathToCheck (Join-Path $RepoRoot "forensic_suite_v2\dashboards\cockpit\main.py") "cockpit main"
Check-Path -PathToCheck (Join-Path $RepoRoot "forensic_suite_v2\dashboards\cli\dashboard.py") "CLI dashboard"
Check-Path -PathToCheck (Join-Path $RepoRoot "forensic_suite_v2\dashboards\web\run_web.py") "web runner"
Check-Path -PathToCheck (Join-Path $RepoRoot "forensic_suite_v2\dashboards\web\app.py") "web app"
Check-Path -PathToCheck (Join-Path $RepoRoot "forensic_suite_v2\dashboards\data\service.py") "dashboard data service"
Check-Path -PathToCheck (Join-Path $RepoRoot "forensic_suite_v2\config\indexer.yaml") "unified config"

if ($issues.Count -gt 0) {
    Write-Host "Validation FAILED:" -ForegroundColor Red
    $issues | ForEach-Object { Write-Host (" - {0}" -f $_) -ForegroundColor Yellow }
    exit 1
}

Write-Host "Repo layout validation OK." -ForegroundColor Green
Write-Host ""
Write-Host "Verifying dashboard config resolution..." -ForegroundColor Yellow

@'
from forensic_suite_v2.dashboards.data.service import DashboardDataService
s = DashboardDataService()
print("Config path:", s.config_path)
print("Exists:", s.config_path.exists())
'@ | python

if ($LASTEXITCODE -ne 0) {
    Write-Host "Python config verification failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Notes:" -ForegroundColor Yellow
Write-Host ' - Cockpit is a Textual TUI. Exit with Q or Ctrl+C.' -ForegroundColor Gray
Write-Host ' - For the web dashboard, browse to http://127.0.0.1:8000 or http://localhost:8000' -ForegroundColor Gray
Write-Host ' - Do not browse to http://0.0.0.0:8000 ; 0.0.0.0 is a bind address, not a browser URL.' -ForegroundColor Gray

Write-Host ""
Write-Host "Select an option:" -ForegroundColor Yellow
Write-Host "  1. Launch cockpit"
Write-Host "  2. Launch CLI dashboard"
Write-Host "  3. Launch web dashboard"
Write-Host "  4. Print commands only"
Write-Host "  Q. Quit"
Write-Host ""

$choice = Read-Host "Choice"

switch ($choice.ToUpperInvariant()) {
    "1" {
        Write-Host "Launching cockpit..." -ForegroundColor Green
        python -m forensic_suite_v2.dashboards.cockpit.main
    }
    "2" {
        Write-Host "Launching CLI dashboard..." -ForegroundColor Green
        python -m forensic_suite_v2.dashboards.cli.dashboard
    }
    "3" {
        Write-Host "Launching web dashboard..." -ForegroundColor Green
        python -m forensic_suite_v2.dashboards.web.run_web
    }
    "4" {
        Write-Host ""
        Write-Host "Cockpit:" -ForegroundColor Yellow
        Write-Host "python -m forensic_suite_v2.dashboards.cockpit.main" -ForegroundColor Green
        Write-Host ""
        Write-Host "CLI:" -ForegroundColor Yellow
        Write-Host "python -m forensic_suite_v2.dashboards.cli.dashboard" -ForegroundColor Green
        Write-Host ""
        Write-Host "Web:" -ForegroundColor Yellow
        Write-Host "python -m forensic_suite_v2.dashboards.web.run_web" -ForegroundColor Green
        Write-Host ""
        Write-Host "Then browse to: http://127.0.0.1:8000" -ForegroundColor Green
    }
    "Q" {
        Write-Host "Exiting." -ForegroundColor Cyan
    }
    Default {
        Write-Host ("Unknown option: {0}" -f $choice) -ForegroundColor Red
        exit 1
    }
}
