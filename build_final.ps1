[CmdletBinding()]
param(
    [switch]$BuildOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

$DistRoot         = Join-Path $ProjectRoot "dist"
$BundleRoot       = Join-Path $DistRoot "ForensicSuite"
$InstallerPayload = Join-Path $ProjectRoot "installer_payload"
$InstallerOutput  = Join-Path $ProjectRoot "Output"
$WheelPattern     = "forensic_suite_v2-*.whl"

Write-Host "=== ForensicSuite Build Script Starting (V9.3.5) ===" -ForegroundColor Cyan
Write-Host "ProjectRoot      : $ProjectRoot" -ForegroundColor Gray
Write-Host "DistRoot         : $DistRoot" -ForegroundColor Gray
Write-Host "BundleRoot       : $BundleRoot" -ForegroundColor Gray
Write-Host "InstallerPayload : $InstallerPayload" -ForegroundColor Gray
Write-Host "InstallerOutput  : $InstallerOutput" -ForegroundColor Gray

function Assert-LastExitCode {
    param(
        [int]$Code,
        [string]$Step
    )
    if ($Code -ne 0) {
        Write-Host "[ERROR] $Step failed with exit code $Code" -ForegroundColor Red
        exit $Code
    }
}

# ---------------------------------------------------------------------------
# 1. Clean build artifacts
# ---------------------------------------------------------------------------
Write-Host "`n=== [1/5] Cleaning build artifacts ===" -ForegroundColor Yellow
Remove-Item -Recurse -Force (Join-Path $ProjectRoot "build") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $DistRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $DistRoot -Force | Out-Null

# ---------------------------------------------------------------------------
# 2. Build wheel once
# ---------------------------------------------------------------------------
Write-Host "`n=== [2/5] Building Python wheel ===" -ForegroundColor Yellow
python -m build
Assert-LastExitCode -Code $LASTEXITCODE -Step "python -m build"

$wheel = Get-ChildItem $DistRoot -Filter $WheelPattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $wheel) {
    Write-Host "[ERROR] Wheel build completed but no wheel was found in $DistRoot" -ForegroundColor Red
    exit 21
}

Write-Host "[OK] Wheel built: $($wheel.Name)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Build PyInstaller bundle once
# ---------------------------------------------------------------------------
Write-Host "`n=== [3/5] Building PyInstaller bundle ===" -ForegroundColor Yellow
& $Global:PythonExe -m PyInstaller ForensicSuite.spec
Assert-LastExitCode -Code $LASTEXITCODE -Step "PyInstaller"

if (-not (Test-Path $BundleRoot)) {
    Write-Host "[ERROR] Expected PyInstaller bundle missing: $BundleRoot" -ForegroundColor Red
    exit 22
}

Write-Host "[OK] PyInstaller bundle confirmed at: $BundleRoot" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. Refresh installer payload exactly once
# ---------------------------------------------------------------------------
Write-Host "`n=== [4/5] Refreshing installer payload ===" -ForegroundColor Yellow
& (Join-Path $ProjectRoot "scripts\refresh_installer_payload.ps1") `
    -Root $ProjectRoot `
    -PayloadRoot $InstallerPayload
Assert-LastExitCode -Code $LASTEXITCODE -Step "refresh_installer_payload.ps1"

$payloadCount = (Get-ChildItem $InstallerPayload -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
if ($payloadCount -lt 1) {
    Write-Host "[ERROR] installer_payload is empty after refresh: $InstallerPayload" -ForegroundColor Red
    exit 23
}

Write-Host "[OK] installer_payload file count: $payloadCount" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 5. Compile Inno Setup installer once
# ---------------------------------------------------------------------------
Write-Host "`n=== [5/5] Compiling Inno Setup installer ===" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $InstallerOutput -Force | Out-Null

& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (Join-Path $ProjectRoot "installer_script.iss")
Assert-LastExitCode -Code $LASTEXITCODE -Step "Inno Setup"

$installerExe = Join-Path $InstallerOutput "ForensicSuiteV2-Setup.exe"
if (-not (Test-Path $installerExe)) {
    Write-Host "[ERROR] Inno Setup reported success but installer EXE was not found: $installerExe" -ForegroundColor Red
    exit 24
}

Write-Host "`nBUILD SUCCESSFUL!" -ForegroundColor Green
Write-Host "Installer: $installerExe" -ForegroundColor Green

if ($BuildOnly) {
    Write-Host "=== Build complete. Skipping deployment due to -BuildOnly ===" -ForegroundColor Yellow
}

exit 0
