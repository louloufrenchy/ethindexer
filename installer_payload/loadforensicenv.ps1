# ---------------------------------------------
# loadforensicenv.ps1
# Bootstrap Script for forensic_suite_v2
# ---------------------------------------------
# This script:
# 1. Ensures Python or py launcher is available
# 2. Creates a Python virtual environment (if missing)
# 3. Activates it safely
# 4. Installs requirements
# 5. Installs forensic_suite_v2 as editable CLI
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
# 0. Validate Python availability (robust)
# ---------------------------------------------
Step "Checking Python availability"

$python = Get-Command python -ErrorAction SilentlyContinue
$pylauncher = Get-Command py -ErrorAction SilentlyContinue

if ($python) {
    Write-Host "Python found at: $($python.Source)" -ForegroundColor Green
    $pythonCmd = "python"
}
elseif ($pylauncher) {
    Write-Host "Python launcher found at: $($pylauncher.Source)" -ForegroundColor Green
    $pythonCmd = "py"
}
else {
    Write-Host "ERROR: Python is not available on PATH." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------
# 1. Handle --force-rebuild
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
# 2. Create virtual environment
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
# 3. Activate virtual environment
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
# 4. Install requirements
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

# ---------------------------------------------
# 5. Install forensic_suite_v2 as editable CLI
# ---------------------------------------------
#Step "Installing forensic_suite_v2 as editable CLI"

#if (-not $dryRun) {
#    pip install -e .
#    if ($LASTEXITCODE -ne 0) {
#        Write-Host "ERROR: Failed to install forensic_suite_v2." -ForegroundColor Red
#        exit 1
#    }
#}

# ---------------------------------------------
# 6. Optional: --check-endpoints
# ---------------------------------------------
if ($checkEndpoints) {
    Step "Checking RPC endpoints"

    if ($dryRun) {
        Write-Host "[DRY RUN] Would run endpoint checks here." -ForegroundColor Yellow
    } else {

        $pythonCode = @"
import aiohttp, asyncio, os
from dotenv import load_dotenv
load_dotenv()

async def test(url):
    try:
        async with aiohttp.ClientSession() as s:
            async with s.post(url.rstrip('/') + '/wallet/getnowblock', json={}) as r:
                print(url, '→', r.status)
    except Exception as e:
        print(url, '→ ERROR:', e)

async def main():
    urls = [
        os.getenv('QUICKNODE_TRON_ENDPOINT_1'),
        os.getenv('QUICKNODE_TRON_ENDPOINT_2'),
        os.getenv('QUICKNODE_ETH_ENDPOINT_1'),
        os.getenv('QUICKNODE_BTC_ENDPOINT_1'),
    ]
    await asyncio.gather(*(test(u) for u in urls if u))

asyncio.run(main())
"@

        python -c $pythonCode
    }
}

# ---------------------------------------------
# Done
# ---------------------------------------------
Write-Host "`n=== Load Environment Complete ===" -ForegroundColor Cyan
