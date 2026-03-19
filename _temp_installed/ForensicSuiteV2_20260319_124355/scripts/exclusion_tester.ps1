# =====================================================================
# exclusion_tester.ps1 (V9.3)
# Shows which pattern (if any) matches each file
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

. "$PSScriptRoot\exclusion_common.ps1" -ExclusionMap $ExclusionMap

Write-Host "=== V9.3 Exclusion Map Tester ==="
Write-Host "Repo A Suite:  $RepoA_Suite"
Write-Host "Exclusion Map: $ExclusionMap"
Write-Host ""

$rows = Import-Csv $MappingCsv | Where-Object { $_.RelativePath -like "forensic_suite_v2\*" }

$result = foreach ($row in $rows) {
    $rel = $row.RelativePath
    $matched = $null

    foreach ($p in $Global:ExclusionPatterns) {
        if (Test-Excluded $rel) {
            $matched = $p
            break
        }
    }

    [PSCustomObject]@{
        RelativePath   = $rel
        MatchedPattern = $matched ? $matched : "NO MATCH"
    }
}

$result | Format-Table -AutoSize

Write-Host "`n[INFO] Exclusion test complete."
exit 0
