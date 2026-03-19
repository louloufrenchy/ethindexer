<#
.SYNOPSIS
    Builds and prepares a chain-specific indexer configuration for deployment.

.DESCRIPTION
    This script:
      1. Validates .env
      2. Validates the template
      3. Builds indexer.yaml for the selected chain
      4. Places output in RepoA_root\out\

.EXAMPLE
    .\Install-IndexerHost.ps1 -ChainProfile btc
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("btc","eth","tron","full")]
    [string]$ChainProfile
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = Split-Path -Parent $ScriptRoot

$configDir  = Join-Path $RepoRoot "config"
$outDir     = Join-Path $RepoRoot "out"
$envFile    = Join-Path $RepoRoot ".env"

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

switch ($ChainProfile) {
    "btc"  { $template = Join-Path $configDir "indexer.btc.yaml.template" }
    "eth"  { $template = Join-Path $configDir "indexer.eth.yaml.template" }
    "tron" { $template = Join-Path $configDir "indexer.tron.yaml.template" }
    "full" { $template = Join-Path $configDir "indexer.full.yaml.template" }
}

Write-Host "=== Building indexer config for $ChainProfile ===" -ForegroundColor Cyan

$validator = Join-Path $RepoRoot "scripts\validation\Test-IndexerConfig.ps1"
& $validator -ConfigPath $template -EnvPath $envFile

$outputConfig = Join-Path $outDir "indexer.$ChainProfile.yaml"

$builder = Join-Path $RepoRoot "scripts\build\Expand-IndexerConfig.ps1"
& $builder -EnvFile $envFile -TemplateFile $template -OutputFile $outputConfig

Write-Host "[OK] Built: $outputConfig" -ForegroundColor Green
