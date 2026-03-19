# =====================================================================
# Forensic Suite v2 – Hardened build.ps1
# Prevents Dropbox/Defender file locks by forcing local temp directories
# Ensures clean wheel build and copies to installer_payload
# =====================================================================

Write-Host "=== Building forensic-suite-v2 wheel ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------
# 1. Force build temp directories into a local folder (not Dropbox)
# ---------------------------------------------------------------------
$LocalTemp = Join-Path $PSScriptRoot "build_tmp"
if (Test-Path $LocalTemp) {
    Remove-Item -Recurse -Force $LocalTemp -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $LocalTemp | Out-Null

$env:TEMP = $LocalTemp
$env:TMP  = $LocalTemp

# ---------------------------------------------------------------------
# 2. Ensure dist/ exists and is clean
# ---------------------------------------------------------------------
$dist = Join-Path $PSScriptRoot "dist"
if (Test-Path $dist) {
    Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $dist | Out-Null

# ---------------------------------------------------------------------
# 3. Build wheel using python -m build
# ---------------------------------------------------------------------
Write-Host "* Running python -m build ..." -ForegroundColor Yellow

python -m pip install --upgrade pip build --quiet

python -m build --outdir "$dist"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Build failed." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------
# 4. Copy wheel to installer_payload
# ---------------------------------------------------------------------
$payload = Join-Path $PSScriptRoot "installer_payload"
$wheel = Get-ChildItem "$dist\*.whl" | Select-Object -First 1

if (-not $wheel) {
    Write-Host "[ERROR] No wheel found in dist/." -ForegroundColor Red
    exit 1
}

Copy-Item $wheel.FullName -Destination $payload -Force

Write-Host "Wheel built and copied to installer_payload: $($wheel.Name)" -ForegroundColor Green

# ---------------------------------------------------------------------
# 5. Cleanup temp folder
# ---------------------------------------------------------------------
Write-Host "* Cleaning up temp build directory ..." -ForegroundColor Yellow
Remove-Item -Recurse -Force $LocalTemp -ErrorAction SilentlyContinue

Write-Host "=== Build complete ===" -ForegroundColor Cyan
