<#
.SYNOPSIS
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

.EXAMPLE
    .\build_and_deploy.ps1 -BuildOnly

.EXAMPLE
    .\build_and_deploy.ps1 -Deploy -BlueGreen
#>

param(
    [switch]$BuildOnly,
    [switch]$Deploy,
    [switch]$BlueGreen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

# -------------------------------
# Step 1 — Clean build artifacts
# -------------------------------
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
if (-not $WheelFile) {
    throw "Wheel build failed — no wheel found in $WheelOutput"
}

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

$ISCC = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $ISCC)) {
    throw "ISCC.exe not found at $ISCC"
}

& $ISCC $InstallerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

$InstallerExe = Get-ChildItem $InstallerOutput -Filter "*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $InstallerExe) {
    throw "Installer build failed — no .exe found in $InstallerOutput"
}

Write-Host "[OK] Installer built: $($InstallerExe.FullName)" -ForegroundColor Green
Write-Host ""

# -------------------------------
# Build-only mode
# -------------------------------
if ($BuildOnly -and -not $Deploy) {
    Write-Host "=== Build complete. Skipping deployment due to -BuildOnly ===" -ForegroundColor Cyan
    Write-Host "Installer: $($InstallerExe.FullName)" -ForegroundColor Green
    exit 0
}

# -------------------------------
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
    Write-Host "Build complete. Deployment skipped (no -Deploy flag)." -ForegroundColor Yellow
}

Write-Host "=== All tasks complete ===" -ForegroundColor Cyan
