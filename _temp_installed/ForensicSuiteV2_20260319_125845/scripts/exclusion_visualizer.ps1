# =====================================================================
# exclusion_visualizer.ps1 (V9.3)
# Color-coded tree with per-folder stats
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

Write-Host "=== V9.3 Exclusion Map Visualizer (with Stats) ==="
Write-Host "Repo A Suite:  $RepoA_Suite"
Write-Host "Exclusion Map: $ExclusionMap"
Write-Host ""

$rows = Import-Csv $MappingCsv | Where-Object { $_.RelativePath -like "forensic_suite_v2\*" }

# Build folder stats
$FolderStats = @{}
$FolderStatus = @{}

foreach ($row in $rows) {
    $rel = $row.RelativePath
    $parts = $rel.Split("\")
    for ($i=1; $i -le $parts.Count; $i++) {
        $folder = ($parts[0..($i-1)] -join "\")
        if (!$FolderStats.ContainsKey($folder)) {
            $FolderStats[$folder] = [PSCustomObject]@{
                Included = 0
                Excluded = 0
                Total    = 0
            }
        }
        $FolderStats[$folder].Total++

        if (Test-Excluded $rel) {
            $FolderStats[$folder].Excluded++
        } else {
            $FolderStats[$folder].Included++
        }
    }
}

foreach ($f in $FolderStats.Keys) {
    $s = $FolderStats[$f]
    if ($s.Included -eq $s.Total) { $FolderStatus[$f] = "Included" }
    elseif ($s.Excluded -eq $s.Total) { $FolderStatus[$f] = "Excluded" }
    else { $FolderStatus[$f] = "Partial" }
}

function Print-Tree {
    param([string]$Path, [string]$Prefix = "")

    $status = $FolderStatus[$Path]
    $stats  = $FolderStats[$Path]

    switch ($status) {
        "Included" { $color = "Green" }
        "Excluded" { $color = "Red" }
        "Partial"  { $color = "Yellow" }
    }

    Write-Host "$Prefix$Path  [$($stats.Included) included, $($stats.Excluded) excluded, $($stats.Total) total]" -ForegroundColor $color

    $children = $FolderStats.Keys |
        Where-Object { $_ -like "$Path\*" -and ($_ -split "\\").Count -eq (($Path -split "\\").Count + 1) } |
        Sort-Object

    foreach ($child in $children) {
        Print-Tree -Path $child -Prefix ("$Prefix    ")
    }
}

Print-Tree "forensic_suite_v2"
exit 0
