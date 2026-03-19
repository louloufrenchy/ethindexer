# =====================================================================
# validate_installer_payload.ps1 (V9.3)
# STRICT VALIDATION FOR INSTALLER PAYLOAD
# Ensures:
#   - Latest wheel is staged
#   - Scripts are in sync with authoritative scripts\
#   - No drift, no missing files, no contamination
# =====================================================================

param()

$ErrorActionPreference = "Stop"

# Authoritative repo root
$root = $Global:PrimaryRoot
if (-not $root) {
    $root = Split-Path -Parent $PSCommandPath
}

$payloadRoot    = Join-Path $root "installer_payload"
$payloadWheel   = Join-Path $payloadRoot "wheel"
$payloadScripts = Join-Path $payloadRoot "scripts"
$srcScripts     = Join-Path $root "scripts"
$srcDist        = Join-Path $root "dist"

Write-Host "=== Installer Payload Validator (V9.3) ===" -ForegroundColor Cyan
Write-Host "Root: $root"
Write-Host "Payload: $payloadRoot"
Write-Host ""

# ---------------------------------------------------------------------
# 1. Validate wheel presence + freshness
# ---------------------------------------------------------------------
Write-Host "[1/4] Checking wheel freshness..." -ForegroundColor Cyan

if (-not (Test-Path $payloadWheel)) {
    Write-Host "[FAIL] installer_payload\wheel folder missing." -ForegroundColor Red
    exit 10
}

if (-not (Test-Path $srcDist)) {
    Write-Host "[FAIL] dist folder missing at $srcDist" -ForegroundColor Red
    exit 11
}

$latestSrcWheel = Get-ChildItem $srcDist -Filter "forensic_suite_v2-*.whl" |
                  Sort-Object LastWriteTime -Descending |
                  Select-Object -First 1

if (-not $latestSrcWheel) {
    Write-Host "[FAIL] No wheel found in $srcDist" -ForegroundColor Red
    exit 12
}

$payloadWheelFile = Get-ChildItem $payloadWheel -Filter "forensic_suite_v2-*.whl" |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1

if (-not $payloadWheelFile) {
    Write-Host "[FAIL] No wheel found in installer_payload\wheel" -ForegroundColor Red
    exit 13
}

if ($payloadWheelFile.Name -ne $latestSrcWheel.Name) {
    Write-Host "[FAIL] Wheel mismatch:" -ForegroundColor Red
    Write-Host "  Latest built: $($latestSrcWheel.Name)"
    Write-Host "  Payload has: $($payloadWheelFile.Name)"
    exit 14
}

Write-Host "[OK] Wheel is latest: $($payloadWheelFile.Name)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------------
# 2. Validate script sync (authoritative scripts\ → installer_payload\scripts)
# ---------------------------------------------------------------------
Write-Host "[2/4] Checking script sync..." -ForegroundColor Cyan

if (-not (Test-Path $payloadScripts)) {
    Write-Host "[FAIL] installer_payload\scripts folder missing." -ForegroundColor Red
    exit 20
}

$srcFiles = Get-ChildItem $srcScripts -File -Recurse
$payloadFiles = Get-ChildItem $payloadScripts -File -Recurse

$missing = @()
$extra   = @()
$drift   = @()

foreach ($src in $srcFiles) {
    $rel = $src.FullName.Substring($srcScripts.Length).TrimStart("\")
    $dest = Join-Path $payloadScripts $rel

    if (-not (Test-Path $dest)) {
        $missing += $rel
        continue
    }

    $hashA = (Get-FileHash $src.FullName -Algorithm SHA256).Hash
    $hashB = (Get-FileHash $dest -Algorithm SHA256).Hash

    if ($hashA -ne $hashB) {
        $drift += $rel
    }
}

foreach ($p in $payloadFiles) {
    $rel = $p.FullName.Substring($payloadScripts.Length).TrimStart("\")
    $src = Join-Path $srcScripts $rel

    if (-not (Test-Path $src)) {
        $extra += $rel
    }
}

if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $drift.Count -eq 0) {
    Write-Host "[OK] Scripts are in perfect sync." -ForegroundColor Green
} else {
    if ($missing.Count -gt 0) {
        Write-Host "`n[FAIL] Missing scripts in payload:" -ForegroundColor Red
        $missing | ForEach-Object { Write-Host "  $_" }
    }
    if ($extra.Count -gt 0) {
        Write-Host "`n[FAIL] Extra scripts in payload:" -ForegroundColor Red
        $extra | ForEach-Object { Write-Host "  $_" }
    }
    if ($drift.Count -gt 0) {
        Write-Host "`n[FAIL] Drifted scripts (hash mismatch):" -ForegroundColor Red
        $drift | ForEach-Object { Write-Host "  $_" }
    }
    exit 21
}

Write-Host ""

# ---------------------------------------------------------------------
# 3. Validate no contamination (unexpected files)
# ---------------------------------------------------------------------
Write-Host "[3/4] Checking for contamination..." -ForegroundColor Cyan

# Strict allow-list for top-level payload contents
$allowedTop = @(
    "wheel",
    "scripts",
    "forensic_suite_v2",
    "python",
    "tools",
    "bootstrap.ps1",
    "env.template.json",
    "dot_env.template",
    "requirements.txt"
)

$topItems = Get-ChildItem $payloadRoot

foreach ($item in $topItems) {
    if ($item.PSIsContainer) {
        # Allowed directories
        if ($allowedTop -contains $item.Name) { continue }
    } else {
        # Allowed files
        if ($allowedTop -contains $item.Name) { continue }
    }

    Write-Host "[FAIL] Unexpected item in installer_payload: $($item.Name)" -ForegroundColor Red
    exit 30
}

Write-Host "[OK] No contamination detected." -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------------
# 4. Final success
# ---------------------------------------------------------------------
Write-Host "[SUCCESS] Installer payload is clean, synced, and ready for deployment." -ForegroundColor Green
exit 0
