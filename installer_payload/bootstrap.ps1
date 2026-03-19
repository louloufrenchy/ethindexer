# ---------------------------------------------
<<<<<<< HEAD
# bootstrap.ps1 – Installer Bootstrap (Hardened)
# ---------------------------------------------
Write-Host "=== Forensic Suite Installer Bootstrap ===" -ForegroundColor Cyan

# [PHASE 1] Secrets & Environment Setup
$secretRoot = "C:\forensic_secrets"
if (!(Test-Path $secretRoot)) { New-Item -ItemType Directory -Path $secretRoot | Out-Null }
$env:FORENSIC_SECRET_PATH = "$secretRoot\env.json"

# [PHASE 2] Python Validation
$pythonCmd = if (Get-Command python -ErrorAction SilentlyContinue) { "python" } else { "py" }
if (!$pythonCmd) { Write-Host "ERROR: Python not found." -ForegroundColor Red; exit 1 }

# [PHASE 3] Virtual Environment (The Missing Step)
if (!(Test-Path "venv")) {
    Write-Host ">>> Creating Virtual Environment..." -ForegroundColor Yellow
    & $pythonCmd -m venv venv
}

# [PHASE 4] Install Forensic Suite 0.1.2
Write-Host ">>> Installing Forensic Suite Payload..." -ForegroundColor Yellow
$wheel = Get-ChildItem -Filter "forensic_suite_v2-0.1.2-*.whl" | Select-Object -First 1
if ($wheel) {
    & ".\venv\Scripts\python.exe" -m pip install --upgrade pip | Out-Null
    & ".\venv\Scripts\python.exe" -m pip install $wheel.FullName
} else {
    Write-Host "WARNING: No wheel found for installation." -ForegroundColor Red
}

# [PHASE 5] Create Launchers/Logs
if (!(Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" | Out-Null }
Write-Host "`nBootstrap complete. Ready for launch." -ForegroundColor Cyan
=======
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
$secretRoot = "F:\forensic_secrets"

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
>>>>>>> master
