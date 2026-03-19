<#
.SYNOPSIS
<<<<<<< HEAD
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
=======
    Builds the Python wheel, refreshes installer_payload, builds the installer, and optionally deploys it.

.DESCRIPTION
    This script performs the following steps:
      1. Cleans build artifacts (dist/, Output/)
      2. Rebuilds the Python wheel into dist/
      3. Refreshes installer_payload via scripts\refresh_installer_payload.ps1 (authoritative, strict allow-list)
      4. Builds the installer using Inno Setup (ISCC.exe) from installer_payload
      5. Optionally deploys using deploy_suite.ps1 to the cluster

.PARAMETER BuildOnly
    Rebuilds the wheel, refreshes payload, builds installer, but skips deployment.

.PARAMETER Deploy
    After building, runs the deployment script to deploy to all hosts.

.PARAMETER BlueGreen
    Enables blue/green deployment mode for the deployment script.
>>>>>>> master

.EXAMPLE
    .\build_and_deploy.ps1 -BuildOnly

.EXAMPLE
<<<<<<< HEAD
    .\build_and_deploy.ps1 -Deploy
=======
    .\build_and_deploy.ps1 -Deploy -BlueGreen
>>>>>>> master
#>

param(
    [switch]$BuildOnly,
<<<<<<< HEAD
    [switch]$Deploy
=======
    [switch]$Deploy,
    [switch]$BlueGreen
>>>>>>> master
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

<<<<<<< HEAD
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
=======
Write-Host "=== ForensicSuite Build + Deploy Script (Hardened) ===" -ForegroundColor Cyan

# -------------------------------
# Paths & Configuration
# -------------------------------
$ProjectRoot       = Split-Path -Parent $MyInvocation.MyCommand.Path
$WheelOutput       = Join-Path $ProjectRoot "dist"
$InstallerPayload  = Join-Path $ProjectRoot "installer_payload"
$InstallerScript   = Join-Path $ProjectRoot "installer_script.iss"
$InstallerOutput   = Join-Path $ProjectRoot "Output"
$RefreshPayloadPs1 = Join-Path $ProjectRoot "scripts\refresh_installer_payload.ps1"
$DeployScript      = Join-Path $ProjectRoot "deploy_suite.ps1"

# Define the Cluster IPs
$ClusterIPs = @(
    "192.168.0.199",
    "192.168.0.28",
    "192.168.0.146",
    "192.168.0.165"
)

Write-Host "ProjectRoot      : $ProjectRoot"      -ForegroundColor DarkGray
Write-Host "WheelOutput      : $WheelOutput"      -ForegroundColor DarkGray
Write-Host "InstallerPayload : $InstallerPayload" -ForegroundColor DarkGray
Write-Host "InstallerOutput  : $InstallerOutput"  -ForegroundColor DarkGray
Write-Host ""
>>>>>>> master

# -------------------------------
# Step 1 — Clean build artifacts
# -------------------------------
<<<<<<< HEAD
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

=======
Write-Host "=== [1/4] Cleaning build artifacts ===" -ForegroundColor Yellow

if (Test-Path $WheelOutput) {
    Remove-Item $WheelOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $WheelOutput | Out-Null

if (Test-Path $InstallerOutput) {
    Remove-Item $InstallerOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallerOutput | Out-Null

Write-Host "[OK] dist/ and Output/ cleaned." -ForegroundColor Green
Write-Host ""

# -------------------------------
# Step 2 — Build Python wheel (dist/)
# -------------------------------
Write-Host "=== [2/4] Building Python wheel ===" -ForegroundColor Yellow

Push-Location $ProjectRoot
python -m build
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "Wheel build failed (python -m build)."
}
Pop-Location

$WheelFile = Get-ChildItem $WheelOutput -Filter "*.whl" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
>>>>>>> master
if (-not $WheelFile) {
    throw "Wheel build failed — no wheel found in $WheelOutput"
}

<<<<<<< HEAD
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
=======
Write-Host "[OK] Wheel built: $($WheelFile.Name)" -ForegroundColor Green
Write-Host ""

# -------------------------------
# Step 3 — Refresh installer_payload (authoritative, strict allow-list)
# -------------------------------
Write-Host "=== [3/4] Refreshing installer_payload (strict, authoritative) ===" -ForegroundColor Yellow

if (-not (Test-Path $RefreshPayloadPs1)) {
    throw "refresh_installer_payload.ps1 not found at $RefreshPayloadPs1"
}

# Ensure installer_payload exists and is clean before refresh
if (Test-Path $InstallerPayload) {
    Remove-Item $InstallerPayload -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallerPayload | Out-Null

# Call the authoritative payload builder
& $RefreshPayloadPs1
if ($LASTEXITCODE -ne 0) {
    throw "refresh_installer_payload.ps1 failed with exit code $LASTEXITCODE"
}

Write-Host "[OK] installer_payload refreshed." -ForegroundColor Green
Write-Host ""

# -------------------------------
# Step 4 — Build installer via Inno Setup (read-only payload)
# -------------------------------
Write-Host "=== [4/4] Building installer via Inno Setup ===" -ForegroundColor Yellow

if (-not (Test-Path $InstallerScript)) {
    throw "Installer script not found at $InstallerScript"
}

if (-not (Test-Path $InstallerPayload)) {
    throw "installer_payload folder missing at $InstallerPayload"
}
>>>>>>> master

$ISCC = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $ISCC)) {
    throw "ISCC.exe not found at $ISCC"
}

<<<<<<< HEAD
$InstallerScriptFull = (Resolve-Path $InstallerScript).Path

Write-Host "Using installer script: $InstallerScriptFull" -ForegroundColor Cyan

& $ISCC $InstallerScriptFull

$InstallerExe = Get-ChildItem $InstallerOutput -Filter "*.exe" | Select-Object -First 1

=======
& $ISCC $InstallerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

$InstallerExe = Get-ChildItem $InstallerOutput -Filter "*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
>>>>>>> master
if (-not $InstallerExe) {
    throw "Installer build failed — no .exe found in $InstallerOutput"
}

<<<<<<< HEAD
Write-Host "Installer built: $($InstallerExe.Name)" -ForegroundColor Green

# Copy installer into installer_payload for orchestrator
Copy-Item $InstallerExe.FullName -Destination $InstallerPayload -Force

Write-Host "Installer copied to payload: $InstallerPayload" -ForegroundColor Green

# -------------------------------
# Step 5 — Build-only mode
# -------------------------------
if ($BuildOnly -and -not $Deploy) {
    Write-Host "=== Build complete. Skipping deployment due to -BuildOnly ===" -ForegroundColor Cyan
=======
Write-Host "[OK] Installer built: $($InstallerExe.FullName)" -ForegroundColor Green
Write-Host ""

# -------------------------------
# Build-only mode
# -------------------------------
if ($BuildOnly -and -not $Deploy) {
    Write-Host "=== Build complete. Skipping deployment due to -BuildOnly ===" -ForegroundColor Cyan
    Write-Host "Installer: $($InstallerExe.FullName)" -ForegroundColor Green
>>>>>>> master
    exit 0
}

# -------------------------------
<<<<<<< HEAD
# Step 6 — Deployment (optional)
# -------------------------------
if ($Deploy) {
    Write-Host "=== Starting orchestrator deployment ===" -ForegroundColor Cyan

    Import-Module "$ProjectRoot\ForensicSuite.Orchestrator" -Force

    Invoke-Orchestration -ManifestPath $ManifestPath

    Write-Host "=== Deployment complete ===" -ForegroundColor Green
}
else {
=======
# Optional: SSH-Based Cluster Deployment
# -------------------------------
if ($Deploy) {
    Write-Host "=== Starting SSH-Based Cluster Deployment ===" -ForegroundColor Cyan

    if (-not (Test-Path $DeployScript)) {
        throw "Deployment script not found at $DeployScript"
    }

    foreach ($IP in $ClusterIPs) {
        try {
            Write-Host "`n>>> Orchestrating Deployment to: $IP" -ForegroundColor Cyan
            & $DeployScript -TargetHost $IP -InstallerPath $InstallerExe.FullName -BlueGreen:$BlueGreen
        } catch {
            Write-Host "[ERROR] Failed to deploy to $IP : $($_.Exception.Message)" -ForegroundColor Red
            # Continue to next host even if one fails
        }
    }

    Write-Host "`n=== Cluster Deployment complete ===" -ForegroundColor Green
} else {
>>>>>>> master
    Write-Host "Build complete. Deployment skipped (no -Deploy flag)." -ForegroundColor Yellow
}

Write-Host "=== All tasks complete ===" -ForegroundColor Cyan
