<#
.SYNOPSIS
    Builds the Python wheel, builds the installer, and optionally deploys it.

.DESCRIPTION
    This script performs the following steps:
      1. Cleans build artifacts
      2. Rebuilds the Python wheel
      3. Copies the wheel into installer_payload
      4. Builds the installer using Inno Setup (ISCC.exe)
      5. Optionally deploys using the ForensicSuite.Orchestrator module

.PARAMETER BuildOnly
    Rebuilds the wheel and installer, but skips deployment.

.PARAMETER Deploy
    After building, runs the orchestrator to deploy to all hosts.

.EXAMPLE
    .\build_and_deploy.ps1 -BuildOnly

.EXAMPLE
    .\build_and_deploy.ps1 -Deploy
#>

param(
    [switch]$BuildOnly,
    [switch]$Deploy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== ForensicSuite Build Script Starting ===" -ForegroundColor Cyan

# -------------------------------
# Paths
# -------------------------------
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WheelSource = $ProjectRoot
$WheelOutput = Join-Path $ProjectRoot "dist"
$InstallerPayload = Join-Path $ProjectRoot "installer_payload"
$InstallerScript = Join-Path $ProjectRoot "installer_script.iss"
$InstallerOutput = Join-Path $ProjectRoot "Output"
$ManifestPath = Join-Path $ProjectRoot "manifests\manifest.psd1"

# -------------------------------
# Step 1 — Clean build artifacts
# -------------------------------
Write-Host "=== Cleaning build artifacts ===" -ForegroundColor Yellow

if (Test-Path $WheelOutput) { Remove-Item $WheelOutput -Recurse -Force }
New-Item -ItemType Directory -Path $WheelOutput | Out-Null

if (Test-Path $InstallerOutput) { Remove-Item $InstallerOutput -Recurse -Force }
New-Item -ItemType Directory -Path $InstallerOutput | Out-Null

# -------------------------------
# Step 2 — Build Python wheel
# -------------------------------
Write-Host "=== Building Python wheel ===" -ForegroundColor Yellow

Push-Location $WheelSource
python -m build
Pop-Location

$WheelFile = Get-ChildItem $WheelOutput -Filter "*.whl" | Select-Object -First 1

if (-not $WheelFile) {
    throw "Wheel build failed — no wheel found in $WheelOutput"
}

Write-Host "Wheel built: $($WheelFile.Name)" -ForegroundColor Green

# -------------------------------
# Step 3 — Copy wheel into installer payload
# -------------------------------
Write-Host "=== Copying wheel into installer payload ===" -ForegroundColor Yellow

Copy-Item $WheelFile.FullName -Destination $InstallerPayload -Force

# -------------------------------
# Step 4 — Build installer via Inno Setup
# -------------------------------
Write-Host "=== Building installer via Inno Setup ===" -ForegroundColor Yellow

$ISCC = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $ISCC)) {
    throw "ISCC.exe not found at $ISCC"
}

$InstallerScriptFull = (Resolve-Path $InstallerScript).Path

Write-Host "Using installer script: $InstallerScriptFull" -ForegroundColor Cyan

& $ISCC $InstallerScriptFull

$InstallerExe = Get-ChildItem $InstallerOutput -Filter "*.exe" | Select-Object -First 1

if (-not $InstallerExe) {
    throw "Installer build failed — no .exe found in $InstallerOutput"
}

Write-Host "Installer built: $($InstallerExe.Name)" -ForegroundColor Green

# Copy installer into installer_payload for orchestrator
Copy-Item $InstallerExe.FullName -Destination $InstallerPayload -Force

Write-Host "Installer copied to payload: $InstallerPayload" -ForegroundColor Green

# -------------------------------
# Step 5 — Build-only mode
# -------------------------------
if ($BuildOnly -and -not $Deploy) {
    Write-Host "=== Build complete. Skipping deployment due to -BuildOnly ===" -ForegroundColor Cyan
    exit 0
}

# -------------------------------
# Step 6 — Deployment (optional)
# -------------------------------
if ($Deploy) {
    Write-Host "=== Starting orchestrator deployment ===" -ForegroundColor Cyan

    Import-Module "$ProjectRoot\ForensicSuite.Orchestrator" -Force

    Invoke-Orchestration -ManifestPath $ManifestPath

    Write-Host "=== Deployment complete ===" -ForegroundColor Green
}
else {
    Write-Host "Build complete. Deployment skipped (no -Deploy flag)." -ForegroundColor Yellow
}

Write-Host "=== All tasks complete ===" -ForegroundColor Cyan
