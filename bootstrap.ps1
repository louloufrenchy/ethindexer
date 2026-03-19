# ---------------------------------------------
# bootstrap.ps1 – Installer Bootstrap
# ---------------------------------------------
# Ensures:
# - Secrets directory exists
# - FORENSIC_SECRET_PATH is set
# - Python environment is validated
# - Suite is ready to run
# ---------------------------------------------

Write-Host "=== Forensic Suite Installer Bootstrap ===" -ForegroundColor Cyan

# ---------------------------------------------
# 1. Ensure secrets directory exists
# ---------------------------------------------
<<<<<<< HEAD
$secretRoot = "C:\forensic_secrets"
=======
$secretRoot = "F:\forensic_secrets"
>>>>>>> master

if (!(Test-Path $secretRoot)) {
    Write-Host "Creating secrets directory at $secretRoot" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $secretRoot | Out-Null
} else {
    Write-Host "Secrets directory already exists: $secretRoot" -ForegroundColor DarkGray
}

# ---------------------------------------------
# 2. Set environment variable for Python loader
# ---------------------------------------------
$env:FORENSIC_SECRET_PATH = "$secretRoot\env.json"
Write-Host "FORENSIC_SECRET_PATH set to $env:FORENSIC_SECRET_PATH" -ForegroundColor Green

# ---------------------------------------------
# 3. Validate Python availability
# ---------------------------------------------
Write-Host "Checking Python availability..." -ForegroundColor Cyan

$python = Get-Command python -ErrorAction SilentlyContinue
$pylauncher = Get-Command py -ErrorAction SilentlyContinue

if ($python) {
    Write-Host "Python found at: $($python.Source)" -ForegroundColor Green
    $pythonCmd = "python"
} elseif ($pylauncher) {
    Write-Host "Python launcher found at: $($pylauncher.Source)" -ForegroundColor Green
    $pythonCmd = "py"
} else {
    Write-Host "ERROR: Python is not available on PATH." -ForegroundColor Red
    exit 1
}

Write-Host "`nBootstrap complete." -ForegroundColor Cyan
