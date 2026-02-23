# ---------------------------------------------
# loadforensicenv.ps1 – Developer Bootstrap
# ---------------------------------------------
# Ensures:
# - Secrets directory exists (fallback)
# - FORENSIC_SECRET_PATH is set
# - Optional template copied if missing
# - venv created and activated
# - Dependencies installed
# - Editable install refreshed
# ---------------------------------------------

param(
    [switch]$forceRebuild,
    [switch]$checkEndpoints,
    [switch]$dryRun
)

Write-Host "=== forensic_suite_v2 Bootstrap ===" -ForegroundColor Cyan
Set-Location -Path $PSScriptRoot

function Step {
    param($msg)
    Write-Host "`n--- $msg ---" -ForegroundColor Cyan
}

# ---------------------------------------------
# 0. Ensure secrets directory exists (fallback)
# ---------------------------------------------
$secretRoot = "C:\forensic_secrets"

if (!(Test-Path $secretRoot)) {
    Write-Host "Creating secrets directory at $secretRoot" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $secretRoot | Out-Null
} else {
    Write-Host "Secrets directory already exists: $secretRoot" -ForegroundColor DarkGray
}

$env:FORENSIC_SECRET_PATH = "$secretRoot\env.json"
Write-Host "FORENSIC_SECRET_PATH set to $env:FORENSIC_SECRET_PATH" -ForegroundColor Green

# Optional template copy
$template = "$PSScriptRoot\env.template.json"
$target = "$secretRoot\env.json"

if (!(Test-Path $target) -and (Test-Path $template)) {
    Write-Host "Copying env.template.json to $target" -ForegroundColor Yellow
    Copy-Item $template $target
}

# ---------------------------------------------
# 1. Validate Python availability
# ---------------------------------------------
Step "Checking Python availability"

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

# ---------------------------------------------
# 2. Handle --force-rebuild
# ---------------------------------------------
if ($forceRebuild) {
    Step "Force rebuild requested"

    if (Test-Path ".\venv") {
        Write-Host "Deleting existing venv..." -ForegroundColor Yellow
        if (-not $dryRun) {
            Remove-Item -Recurse -Force ".\venv"
        }
    } else {
        Write-Host "No existing venv to delete." -ForegroundColor DarkGray
    }
}

# ---------------------------------------------
# 3. Create virtual environment
# ---------------------------------------------
Step "Creating virtual environment"

if (!(Test-Path ".\venv")) {
    Write-Host "Creating venv..." -ForegroundColor Yellow
    if (-not $dryRun) {
        & $pythonCmd -m venv venv
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to create virtual environment." -ForegroundColor Red
            exit 1
        }
    }
} else {
    Write-Host "Virtual environment already exists." -ForegroundColor DarkGray
}

# ---------------------------------------------
# 4. Activate virtual environment
# ---------------------------------------------
Step "Activating virtual environment"

$activate = ".\venv\Scripts\Activate.ps1"
if (!(Test-Path $activate)) {
    Write-Host "ERROR: Could not find Activate.ps1" -ForegroundColor Red
    exit 1
}

if (-not $dryRun) {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    . $activate
}

Write-Host "Virtual environment activated." -ForegroundColor Green

# ---------------------------------------------
# 5. Install requirements
# ---------------------------------------------
Step "Installing dependencies"

if (Test-Path "requirements.txt") {
    Write-Host "Upgrading pip..." -ForegroundColor Yellow
    if (-not $dryRun) { python -m pip install --upgrade pip }

    Write-Host "Installing requirements..." -ForegroundColor Yellow
    if (-not $dryRun) {
        pip install -r requirements.txt
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to install requirements." -ForegroundColor Red
            exit 1
        }
    }
} else {
    Write-Host "No requirements.txt found. Skipping." -ForegroundColor DarkYellow
}

Write-Host "`n=== Load Environment Complete ===" -ForegroundColor Cyan
