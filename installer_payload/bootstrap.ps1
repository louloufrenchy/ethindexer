# ---------------------------------------------
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
