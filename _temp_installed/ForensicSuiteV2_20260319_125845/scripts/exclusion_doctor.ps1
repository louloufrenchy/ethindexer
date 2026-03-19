# =====================================================================
# exclusion_doctor.ps1 (V9.3)
# Master diagnostic wrapper
# =====================================================================

param(
    [string]$RepoA_Root  = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root",
    [string]$RepoA_Suite = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\forensic_suite_v2",
    [string]$MappingCsv  = "F:\tools\repo_mapping_suite.csv",
    [string]$ExclusionMap = "F:\tools\sync_dev_exclusions_v9.3.yaml"
)

$ErrorActionPreference = "Stop"

Write-Host "=== V9.3 EXCLUSION DOCTOR ==="
Write-Host "Repo A Suite:  $RepoA_Suite"
Write-Host "Exclusion Map: $ExclusionMap"
Write-Host ""

$ScriptsRoot = Join-Path $RepoA_Root "scripts"

$CoverageScript   = Join-Path $ScriptsRoot "exclusion_coverage.ps1"
$TesterScript     = Join-Path $ScriptsRoot "exclusion_tester.ps1"
$VisualizerScript = Join-Path $ScriptsRoot "exclusion_visualizer.ps1"

foreach ($f in @($CoverageScript,$TesterScript,$VisualizerScript)) {
    if (!(Test-Path $f)) { throw "Missing script: $f" }
}

Write-Host ">>> Running Coverage Report..."
& $CoverageScript -RepoA_Suite $RepoA_Suite -MappingCsv $MappingCsv -ExclusionMap $ExclusionMap

Write-Host "`n>>> Running Pattern Tester..."
& $TesterScript -RepoA_Suite $RepoA_Suite -MappingCsv $MappingCsv -ExclusionMap $ExclusionMap

Write-Host "`n>>> Running Tree Visualizer..."
& $VisualizerScript -RepoA_Suite $RepoA_Suite -MappingCsv $MappingCsv -ExclusionMap $ExclusionMap

Write-Host "`n[SUCCESS] Exclusion Doctor complete."
exit 0
