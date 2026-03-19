# scripts\build_wheel.ps1 (V9.3)
# Deterministic wheel build + compatibility shim for legacy build_final.ps1
. $PROFILE
param(
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Primary repo root (authoritative)
$root = $Global:PrimaryRoot
if (-not $root) {
    # Fallback: script directory parent
    $root = (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
}

Write-Host "=== Build-Wheel (V9.3) ==="
Write-Host "Root: $root"

# Ensure legacy expected dist folder exists for downstream copy logic
$fsDist = Join-Path $root "forensic_suite_v2\dist"
if (-not (Test-Path $fsDist)) {
    Write-Host "[INFO] Creating legacy dist folder: $fsDist"
    New-Item -ItemType Directory -Path $fsDist | Out-Null
}

Push-Location $root
try {
    # Delegate to existing build_final.ps1 which already drives:
    #  - python -m build
    #  - wheel creation
    #  - copy into installer payload (once dist path exists)
    $buildScript = Join-Path $root "build_final.ps1"
    if (-not (Test-Path $buildScript)) {
        throw "build_final.ps1 not found at $buildScript"
    }

    Write-Host "=== ForensicSuite Build Script Starting (via build_wheel.ps1) ==="
    & $buildScript -BuildOnly
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        Write-Host "[FAIL] build_final.ps1 returned code $code" -ForegroundColor Red
        exit $code
    }

    Write-Host "[SUCCESS] Wheel build completed via build_final.ps1." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[FATAL] Unhandled exception in build_wheel.ps1: $_" -ForegroundColor Red
    exit 199
}
finally {
    Pop-Location
}
