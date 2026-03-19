# =====================================================================
# build_installer.ps1 (V9.3)
# Deterministic Inno Setup installer build
# =====================================================================

param()

$ErrorActionPreference = "Stop"

# Authoritative repo root
$root = $Global:PrimaryRoot
if (-not $root) {
    $root = Split-Path -Parent $PSCommandPath
}

Write-Host "=== [build_installer] Building installer EXE (V9.3) ==="
Write-Host "Root: $root"

$script = Join-Path $root "build_and_deploy.ps1"
if (-not (Test-Path $script)) {
    throw "build_and_deploy.ps1 not found at $script"
}

Push-Location $root
try {
    Write-Host "[INFO] Running build_and_deploy.ps1 -BuildOnly"
    & $script -BuildOnly

    if ($LASTEXITCODE -ne 0) {
        throw "build_and_deploy.ps1 failed with exit code $LASTEXITCODE"
    }

    $installer = Join-Path $root "Output\ForensicSuiteV2-Setup.exe"
    if (-not (Test-Path $installer)) {
        throw "Installer EXE not found at: $installer"
    }

    Write-Host "[SUCCESS] Installer built: $installer" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[FATAL] build_installer.ps1: $_" -ForegroundColor Red
    exit 199
}
finally {
    Pop-Location
}
