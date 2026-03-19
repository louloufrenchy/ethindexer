<#
.SYNOPSIS
    Deploys a chain‑specific ingestion configuration to a remote host.

.DESCRIPTION
    This script performs a deterministic, multi‑step deployment:
      1. Validates .env and template variables
      2. Builds the chain‑specific indexer.yaml
      3. Copies indexer.yaml + .env to the remote host
      4. Restarts the orchestrator service
      5. Validates ingestion progress

.PARAMETER ChainProfile
    One of: btc, eth, tron, full

.PARAMETER TargetHost
    The remote host IP or hostname.

.PARAMETER RemoteRoot
    Root directory of forensic suite on the remote host.

.EXAMPLE
    .\Deploy-ChainHost.ps1 -ChainProfile btc -TargetHost 192.168.0.172
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("btc","eth","tron","full")]
    [string]$ChainProfile,

    [Parameter(Mandatory=$true)]
    [string]$TargetHost,

    [string]$RemoteRoot = "C:\forensic_suite_v2"
)

Write-Host "=== Deploy-ChainHost.ps1 ===" -ForegroundColor Cyan
Write-Host "Profile: $ChainProfile" -ForegroundColor Gray
Write-Host "Host:    $TargetHost" -ForegroundColor Gray
Write-Host ""

# -----------------------------
# Resolve Repo A root
# -----------------------------
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = Split-Path -Parent $ScriptRoot

$configDir  = Join-Path $RepoRoot "config"
$outDir     = Join-Path $RepoRoot "out"
$envFile    = Join-Path $RepoRoot ".env"

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# -----------------------------
# Select template
# -----------------------------
switch ($ChainProfile) {
    "btc"  { $template = Join-Path $configDir "indexer.btc.yaml.template" }
    "eth"  { $template = Join-Path $configDir "indexer.eth.yaml.template" }
    "tron" { $template = Join-Path $configDir "indexer.tron.yaml.template" }
    "full" { $template = Join-Path $configDir "indexer.full.yaml.template" }
}

if (-not (Test-Path $template)) {
    throw "Template not found: $template"
}

# -----------------------------
# Validate template against .env
# -----------------------------
Write-Host "[1/5] Validating template..." -ForegroundColor Cyan

$validator = Join-Path $RepoRoot "scripts\validation\Test-IndexerConfig.ps1"
& $validator -ConfigPath $template -EnvPath $envFile

Write-Host "[OK] Template validated." -ForegroundColor Green
Write-Host ""

# -----------------------------
# Build chain‑specific config
# -----------------------------
Write-Host "[2/5] Building chain-specific config..." -ForegroundColor Cyan

$outputConfig = Join-Path $outDir "indexer.$ChainProfile.yaml"

$builder = Join-Path $RepoRoot "scripts\build\Expand-IndexerConfig.ps1"
& $builder -EnvFile $envFile -TemplateFile $template -OutputFile $outputConfig

Write-Host "[OK] Built: $outputConfig" -ForegroundColor Green
Write-Host ""

# -----------------------------
# Copy files to remote host
# -----------------------------
Write-Host "[3/5] Copying files to remote host..." -ForegroundColor Cyan

$remoteConfigPath = "$RemoteRoot\forensic_suite_v2\config\indexer.yaml"
$remoteEnvPath    = "F:\forensic_secrets\.env"

scp $outputConfig "forensicuser@$TargetHost:`"$remoteConfigPath`""
scp $envFile      "forensicuser@$TargetHost:`"$remoteEnvPath`""

Write-Host "[OK] Files copied." -ForegroundColor Green
Write-Host ""

# -----------------------------
# Restart orchestrator
# -----------------------------
Write-Host "[4/5] Restarting orchestrator..." -ForegroundColor Cyan

ssh forensicuser@$TargetHost "powershell -Command Restart-Service forensic_orchestrator"

Start-Sleep -Seconds 5

Write-Host "[OK] Orchestrator restarted." -ForegroundColor Green
Write-Host ""

# -----------------------------
# Validate ingestion progress
# -----------------------------
Write-Host "[5/5] Validating ingestion..." -ForegroundColor Cyan

$ingestionTest = Join-Path $RepoRoot "scripts\validation\Test-IngestionProgress.ps1"
& $ingestionTest -TargetHost $TargetHost -WaitSeconds 60

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
