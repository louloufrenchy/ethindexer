<#
.SYNOPSIS
    Bootstrap script for Forensic Suite v2.
    Ensures .venv exists, activates it, and installs dependencies.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
$VenvPath = Join-Path $RepoRoot ".venv"
$VenvActivate = Join-Path $VenvPath "Scripts\Activate.ps1"
$Requirements = Join-Path $RepoRoot "forensic_suite_v2\requirements.runtime.txt"

Write-Host "=== Forensic Suite v2 - Dev Bootstrap ===" -ForegroundColor Cyan
Write-Host "Repo root: $RepoRoot"

# 1. Create virtual environment if missing
if (-not (Test-Path $VenvPath)) {
    Write-Host "Virtual environment not found. Creating..." -ForegroundColor Yellow

    # Try using the 'py' launcher (standard for Windows)
    if (Get-Command py -ErrorAction SilentlyContinue) {
        py -3.11 -m venv $VenvPath
    } else {
        Write-Host "Python launcher 'py' not found. Falling back to 'python'..." -ForegroundColor DarkGray
        python -m venv $VenvPath
    }
} else {
    Write-Host "Virtual environment already exists." -ForegroundColor DarkGray
}

# 2. Verify and Activate
if (Test-Path $VenvActivate) {
    Write-Host "Activating environment..." -ForegroundColor Yellow
    # Set execution policy for the current session to allow script running
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    . $VenvActivate
} else {
    Write-Host "ERROR: Activation script not found at $VenvActivate" -ForegroundColor Red
    exit 1
}

# 3. Install/Update Dependencies
if (Test-Path $Requirements) {
    Write-Host "Installing/Updating requirements..." -ForegroundColor Yellow
    python -m pip install --upgrade pip
    pip install -r $Requirements
}

# 4. Install local package in editable mode
Write-Host "Installing forensic_suite as CLI (Editable)..." -ForegroundColor Yellow
pip install -e .

Write-Host "`n=== Bootstrap Complete - Environment Active ===" -ForegroundColor Green
