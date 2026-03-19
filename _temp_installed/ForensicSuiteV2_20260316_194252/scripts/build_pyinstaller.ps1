# =====================================================================
# build_pyinstaller.ps1 (V9.3)
# Deterministic PyInstaller bundle build
# =====================================================================

param()

$ErrorActionPreference = "Stop"

# Authoritative repo root
$root = $Global:PrimaryRoot
if (-not $root) {
    $root = Split-Path -Parent $PSCommandPath
}

Write-Host "=== [build_pyinstaller] Building PyInstaller bundle (V9.3) ==="
Write-Host "Root: $root"

$spec = Join-Path $root "ForensicSuite.spec"
if (-not (Test-Path $spec)) {
    throw "PyInstaller spec not found: $spec"
}

# Clean old PyInstaller output
$buildDir = Join-Path $root "build"
$distDir  = Join-Path $root "dist"
$outputDir = Join-Path $root "Output"

foreach ($d in @($buildDir, $distDir, $outputDir)) {
    if (Test-Path $d) {
        Write-Host "[CLEAN] Removing $d"
        Remove-Item $d -Recurse -Force
    }
}

New-Item -ItemType Directory -Path $outputDir | Out-Null

Push-Location $root
try {
    Write-Host "[INFO] Ensuring PyInstaller is installed..."
    py -m pip install --upgrade pyinstaller | Out-Null

    Write-Host "[INFO] Running PyInstaller with spec: $spec"
    py -m PyInstaller $spec

    if ($LASTEXITCODE -ne 0) {
        throw "PyInstaller failed with exit code $LASTEXITCODE"
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
