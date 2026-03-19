# Requires -Version 7.0
# Health.ps1

Import-Module "$PSScriptRoot\Orchestrator.psm1" -Force

Write-Host "=== HEALTHCHECK ===" -ForegroundColor Cyan

Invoke-Parallel -StepName "HealthCheck" -Action {
    param($TargetHost)

    $cmd = 'pwsh -NoProfile -Command "Get-Service -Name ForensicSuiteV2 -ErrorAction SilentlyContinue | Select-Object Status,Name"'
    Invoke-Ssh -TargetHost $TargetHost -Command $cmd
} | Out-Null

Write-Host "=== Healthcheck complete ===" -ForegroundColor Green