# =====================================================================
# repair_installer_payload.ps1 (V9.3)
# AUTOMATIC REPAIR OF INSTALLER PAYLOAD
# Ensures:
#   - Latest wheel is staged
#   - Scripts are synced from authoritative scripts\
#   - Drifted, missing, or extra files are corrected
#   - No contamination remains
# =====================================================================

param()

$ErrorActionPreference = "Stop"

# Authoritative repo root
$root = $Global:PrimaryRoot
if (-not $root) {
    $root = Split-Path -Parent $PSCommandPath
}

$payloadRoot     = Join-Path $root "installer_payload"
$payloadWheel    = Join-Path $payloadRoot "wheel"
$payloadScripts  = Join-Path $payloadRoot "scripts"
$srcScripts      = Join-Path $root "scripts"
$srcDist         = Join-Path $root "dist"

Write-Host "=== Repair Installer Payload (V9.3) ===" -ForegroundColor Cyan
Write-Host "Root: $root"
Write-Host ""

# ---------------------------------------------------------------------
# Ensure folder structure exists
# ---------------------------------------------------------------------
foreach ($p in @($payloadRoot, $payloadWheel, $payloadScripts)) {
    if (-not (Test-Path $p)) {
        Write-Host "[CREATE] $p"
        New-Item -ItemType Directory -Path $p | Out-Null
    }
}

# ---------------------------------------------------------------------
# 1. Repair wheel (latest only)
# ---------------------------------------------------------------------
Write-Host "[1/3] Repairing wheel..." -ForegroundColor Cyan

if (-not (Test-Path $srcDist)) {
    throw "dist folder missing at $srcDist"
}

$latestWheel = Get-ChildItem $srcDist -Filter "forensic_suite_v2-*.whl" |
               Sort-Object LastWriteTime -Descending |
               Select-Object -First 1

if (-not $latestWheel) {
    throw "No wheel found in $srcDist"
}

# Remove old wheels
Get-ChildItem $payloadWheel -Filter "*.whl" -ErrorAction SilentlyContinue |
    Remove-Item -Force

# Copy latest wheel
Copy-Item $latestWheel.FullName -Destination $payloadWheel -Force
Write-Host "[OK] Latest wheel copied: $($latestWheel.Name)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------------
# 2. Repair scripts (sync authoritative → payload)
# ---------------------------------------------------------------------
Write-Host "[2/3] Repairing scripts..." -ForegroundColor Cyan

# Remove all payload scripts
Get-ChildItem $payloadScripts -Recurse -File -ErrorAction SilentlyContinue |
    Remove-Item -Force

# Recreate folder structure
Get-ChildItem $payloadScripts -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force

# Copy authoritative scripts
Get-ChildItem $srcScripts -Recurse -File |
    ForEach-Object {
        $rel = $_.FullName.Substring($srcScripts.Length).TrimStart("\")
        $dest = Join-Path $payloadScripts $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir | Out-Null
        }
        Copy-Item $_.FullName -Destination $dest -Force
        Write-Host "[SYNC] $rel"
    }

Write-Host "[OK] Scripts synced." -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------------
# 3. Remove contamination
# ---------------------------------------------------------------------
Write-Host "[3/3] Removing contamination..." -ForegroundColor Cyan

$allowed = @("wheel", "scripts")

Get-ChildItem $payloadRoot |
    Where-Object { $_.Name -notin $allowed } |
    ForEach-Object {
        Write-Host "[REMOVE] Unexpected item: $($_.Name)"
        Remove-Item $_.FullName -Recurse -Force
    }

Write-Host "[OK] Payload cleaned." -ForegroundColor Green
Write-Host ""

Write-Host "[SUCCESS] Installer payload repaired and ready." -ForegroundColor Green
exit 0
