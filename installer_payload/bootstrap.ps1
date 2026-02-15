param(
    [string]$PythonInstaller = "python-3.12.2-amd64.exe",
    [string]$WheelPath = "forensic_suite_v2-0.1.0-py3-none-any.whl"
)

$ErrorActionPreference = "Stop"
Write-Host "=== Forensic Suite v2 Bootstrap ===" -ForegroundColor Cyan

function Get-PythonPath {
    $candidates = @(
        "$env:ProgramFiles\Python312\python.exe",
        "$env:ProgramFiles\Python311\python.exe",
        "$env:ProgramFiles\Python310\python.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

$python = Get-PythonPath
if (-not $python) {
    if (Test-Path $PythonInstaller) {
        Write-Host "Python not found. Installing..." -ForegroundColor Yellow
        & $PythonInstaller /quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1
        Start-Sleep -Seconds 10
        $python = Get-PythonPath
        if (-not $python) {
            Write-Host "Python installation failed or not detected." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Python not found and installer missing." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Using Python: $python" -ForegroundColor Green

if (-not (Test-Path "venv")) {
    Write-Host "Creating virtual environment..." -ForegroundColor Cyan
    & $python -m venv "venv"
}

$venvPython = Join-Path "venv\Scripts" "python.exe"
$venvPip    = Join-Path "venv\Scripts" "pip.exe"

Write-Host "Upgrading pip..." -ForegroundColor Cyan
& $venvPython -m pip install --upgrade pip

Write-Host "Installing forensic_suite_v2 wheel..." -ForegroundColor Cyan
& $venvPip install "$WheelPath"

Write-Host "Bootstrapping database (forensic)..." -ForegroundColor Cyan
& $venvPython "tools\bootstrap_db.py"

Write-Host "Bootstrap complete." -ForegroundColor Green
