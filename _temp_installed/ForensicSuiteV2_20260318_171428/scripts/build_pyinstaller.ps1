# =====================================================================
# build_pyinstaller.ps1 (V9.4)
# Deterministic PyInstaller bundle build using global Python variable
# =====================================================================
. $PROFILE
param()

$ErrorActionPreference = "Stop"

# --- Resolve authoritative repo root ---------------------------------
$root = $Global:PrimaryRoot
if (-not $root) {
    $root = Split-Path -Parent $PSCommandPath
}

Write-Host "=== [build_pyinstaller] Building PyInstaller bundle (V9.4) ==="
Write-Host "Root: $root"

# --- Resolve Python interpreter --------------------------------------
if (-not $Global:PythonExe) {
    throw "[FATAL] Global Python path not defined. Set `$Global:PythonExe in your profile."
}

$PythonExe = $Global:PythonExe

if (-not (Test-Path $PythonExe)) {
    throw "[FATAL] Python interpreter not found at: $PythonExe"
}

Write-Host "[INFO] Using Python: $PythonExe"

# --- Resolve PyInstaller spec file -----------------------------------
$spec = Join-Path $root "ForensicSuite.spec"
if (-not (Test-Path $spec)) {
    throw "[FATAL] PyInstaller spec not found: $spec"
}

# --- Clean old PyInstaller output ------------------------------------
$buildDir  = Join-Path $root "build"
$distDir   = Join-Path $root "dist"
$outputDir = Join-Path $root "Output"

foreach ($d in @($buildDir, $distDir, $outputDir)) {
    if (Test-Path $d) {
        Write-Host "[CLEAN] Removing $d"
        Remove-Item $d -Recurse -Force
    }
}

New-Item -ItemType Directory -Path $outputDir | Out-Null

# --- Run PyInstaller --------------------------------------------------
Push-Location $root
try {
    Write-Host "[INFO] Ensuring PyInstaller is installed..."
    & $PythonExe -m pip install --upgrade pyinstaller | Out-Null

    Write-Host "[INFO] Running PyInstaller with spec: $spec"
    & $PythonExe -m PyInstaller --clean --noconfirm --specpath $root $spec

    if ($LASTEXITCODE -ne 0) {
        throw "[FATAL] PyInstaller failed with exit code $LASTEXITCODE"
    }

    Write-Host "[SUCCESS] PyInstaller bundle built." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[FATAL] build_pyinstaller.ps1: $_" -ForegroundColor Red
    exit 199
}
finally {
    Pop-Location
}
