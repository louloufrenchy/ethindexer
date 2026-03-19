# =====================================================================
# Forensic Suite V2 — Blue/Green Install Script (Authoritative)
# =====================================================================

param(
    [string]$PayloadRoot = "C:\installer_payload",
    [string]$BlueRoot    = "C:\forensic_suite_v2_blue",
    [string]$GreenRoot   = "C:\forensic_suite_v2_green",
    [string]$LinkRoot    = "C:\forensic_suite_v2"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Forensic Suite V2 Blue/Green Install ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------
# 1. Determine inactive slot
# ---------------------------------------------------------------------
$active = $null
if (Test-Path $LinkRoot) {
    try {
        $active = (Get-Item $LinkRoot -Force).Target
    } catch { $active = $null }
}

if ($active -eq $BlueRoot) {
    $target = $GreenRoot
} else {
    $target = $BlueRoot
}

Write-Host "Active slot : $active"
Write-Host "Target slot : $target" -ForegroundColor Yellow

# ---------------------------------------------------------------------
# 2. Replace target slot with payload
# ---------------------------------------------------------------------
Write-Host "Deploying payload to $target ..." -ForegroundColor Cyan

if (Test-Path $target) {
    Remove-Item $target -Recurse -Force
}

New-Item -ItemType Directory -Path $target | Out-Null

Copy-Item "$PayloadRoot\forensic_suite_v2" $target -Recurse -Force
Copy-Item "$PayloadRoot\requirements.txt" $target -Force

# ---------------------------------------------------------------------
# 3. Install Python dependencies
# ---------------------------------------------------------------------
Write-Host "Installing Python dependencies..." -ForegroundColor Cyan

$python = "C:\Program Files\Python314\python.exe"
& $python -m pip install -r "$target\requirements.txt"

# ---------------------------------------------------------------------
# 4. Install Windows services
# ---------------------------------------------------------------------
Write-Host "Installing Windows services..." -ForegroundColor Cyan

$svcScript = Join-Path $target "forensic_suite_v2\scripts\install_services.ps1"
& $svcScript -SuiteRoot $target

# ---------------------------------------------------------------------
# 5. Update symlink atomically
# ---------------------------------------------------------------------
Write-Host "Updating symlink..." -ForegroundColor Cyan

if (Test-Path $LinkRoot) {
    cmd /c rmdir $LinkRoot 2>$null | Out-Null
}

cmd /c mklink /D $LinkRoot $target | Out-Null

Write-Host "Symlink now points to: $target" -ForegroundColor Green

# ---------------------------------------------------------------------
# 6. Start indexers (validator-gated)
# ---------------------------------------------------------------------
Write-Host "Starting indexers..." -ForegroundColor Cyan

$btc = Join-Path $LinkRoot "forensic_suite_v2\btc_indexer\services\run_btc_indexer_v2.py"
& cmd.exe /c "set PYTHONPATH=$LinkRoot && `"$python`" `"$btc`""

Write-Host "=== Deployment Complete ===" -ForegroundColor Green
