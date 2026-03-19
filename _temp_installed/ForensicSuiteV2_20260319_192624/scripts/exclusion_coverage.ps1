# =====================================================================
# exclusion_coverage.ps1 (V9.3)
# Coverage report: how many files each pattern excludes
# =====================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$RepoA_Suite,

    [Parameter(Mandatory=$true)]
    [string]$MappingCsv,

    [Parameter(Mandatory=$true)]
    [string]$ExclusionMap
)

$ErrorActionPreference = "Stop"

# Import common engine
. "$PSScriptRoot\exclusion_common.ps1" -ExclusionMap $ExclusionMap

Write-Host "=== V9.3 Exclusion Map Coverage Report ==="
Write-Host "Repo A Suite:  $RepoA_Suite"
Write-Host "Exclusion Map: $ExclusionMap"
Write-Host ""

$rows = Import-Csv $MappingCsv | Where-Object { $_.RelativePath -like "forensic_suite_v2\*" }

$patterns = $Global:ExclusionPatterns
$coverage = @{}

foreach ($p in $patterns) { $coverage[$p] = 0 }

foreach ($row in $rows) {
    $rel = $row.RelativePath
    foreach ($p in $patterns) {
        if (Test-Excluded $rel) {
            $coverage[$p]++
            break
        }
    }
}

Write-Host "=== Pattern Coverage (how many files each pattern excludes) ===`n"
$coverage.GetEnumerator() | Sort-Object Name | Format-Table Name, Value

Write-Host "`n=== Patterns That Exclude NOTHING ==="
$coverage.GetEnumerator() | Where-Object { $_.Value -eq 0 } | Select-Object Name | Format-Table

Write-Host "`n[INFO] Coverage analysis complete."
exit 0
