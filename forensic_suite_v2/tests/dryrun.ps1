Import-Module ..\ForensicSuite.Orchestrator

Write-Host "=== DRY RUN MODE ===" -ForegroundColor Cyan

$Manifest = Read-OrchestrationManifest -Path ..\manifests\manifest.psd1

foreach ($step in $Manifest.Steps) {
    Write-Host "Would execute step: $($step.Id)"
    Write-Host "  Type: $($step.Type)"
    Write-Host "  Targets: $($Manifest.Hosts | Where-Object { $step.Roles -contains $_.Role } | Select-Object -ExpandProperty Name -join ', ')"
    Write-Host ""
}

Write-Host "Dry run complete."
