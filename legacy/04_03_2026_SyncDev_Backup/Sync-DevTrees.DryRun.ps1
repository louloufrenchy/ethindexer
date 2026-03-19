# =====================================================================
# FILE: scripts\Sync-DevTrees.DryRun.ps1
# =====================================================================
# Sync-DevTrees.DryRun.ps1 (V9.3)
# Authoritative → Runtime-Only DRY RUN with Exclusion Map
# =====================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$MappingCsv
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

Write-Host "=== Sync-DevTrees DRY RUN (V9.3) ===" -ForegroundColor Cyan

if (!(Test-Path $MappingCsv)) {
    Write-Error "Mapping CSV not found: $MappingCsv"
    exit 1
}

# ---------------------------------------------------------------------
# 1. LOAD MAPPING
# ---------------------------------------------------------------------
$Mapping = Import-Csv -Path $MappingCsv
if (-not $Mapping -or $Mapping.Count -eq 0) {
    Write-Error "Mapping CSV is empty or invalid: $MappingCsv"
    exit 2
}

$RepoA_Root = ($Mapping | Select-Object -First 1).SourceRoot
$RepoB_Root = ($Mapping | Select-Object -First 1).DestRoot

Write-Host "Repo A (authoritative root): $RepoA_Root" -ForegroundColor Gray
Write-Host "Repo B (mirror root)       : $RepoB_Root" -ForegroundColor Gray

# ---------------------------------------------------------------------
# 2. LOAD EXCLUSION MAP (YAML-LITE PARSE)
# ---------------------------------------------------------------------
$ExclusionFile = "F:\tools\sync_dev_exclusions_v9.3.yaml"
if (!(Test-Path $ExclusionFile)) {
    Write-Error "Exclusion map not found: $ExclusionFile"
    exit 3
}

$RawLines = Get-Content $ExclusionFile
$Patterns = @()

foreach ($line in $RawLines) {
    $trim = $line.Trim()
    if ($trim -like "- *") {
        $pat = $trim.Substring(1).Trim()
        if ($pat) { $Patterns += $pat }
    }
}

Write-Host "`n[INFO] Loaded $($Patterns.Count) exclusion patterns from V9.3 map." -ForegroundColor Yellow

function Test-Excluded {
    param(
        [string]$RelativePath
    )
    $p = $RelativePath.Replace("\","/").ToLower()
    foreach ($pat in $Patterns) {
        $norm = $pat.Replace("\","/").ToLower()

        # Directory-style patterns
        if ($norm.EndsWith("/")) {
            if ($p -like "$norm*") { return $true }
        }
        # Wildcard patterns
        elseif ($norm -like "*`**" -or $norm -like "*`**/*" -or $norm -like "*`*.*") {
            if ($p -like $norm) { return $true }
        }
        # Simple suffix/prefix matches
        else {
            if ($p -like $norm -or $p.EndsWith($norm)) { return $true }
        }
    }
    return $false
}

# ---------------------------------------------------------------------
# 3. FILTER MAPPING BY EXCLUSIONS
# ---------------------------------------------------------------------
$Included = @()
$Excluded = @()

foreach ($row in $Mapping) {
    $rel = $row.RelativePath
    if (Test-Excluded -RelativePath $rel) {
        $Excluded += $row
    } else {
        $Included += $row
    }
}

Write-Host "`n[INFO] After applying exclusions:" -ForegroundColor Yellow
Write-Host "  Included rows : $($Included.Count)" -ForegroundColor Green
Write-Host "  Excluded rows : $($Excluded.Count)" -ForegroundColor DarkYellow

# ---------------------------------------------------------------------
# 4. REPORT: FILES TO COPY / UPDATE
# ---------------------------------------------------------------------
$ToCopy = $Included | Where-Object { $_.Action -eq "Copy" -or $_.Action -eq "Update" -or -not $_.Action }

if ($ToCopy.Count -gt 0) {
    Write-Host "`n--- Files to COPY/UPDATE into Repo B (after exclusions) ---`n" -ForegroundColor Cyan
    $ToCopy |
        Select-Object RelativePath, SourcePath |
        Format-Table -AutoSize
} else {
    Write-Host "`n[INFO] No files to copy/update after exclusions." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------
# 5. REPORT: FILES TO DELETE FROM REPO B
# ---------------------------------------------------------------------
$ToDelete = $Included | Where-Object { $_.Action -eq "Delete" }

if ($ToDelete.Count -gt 0) {
    Write-Host "`n--- Files to DELETE from Repo B (after exclusions) ---`n" -ForegroundColor Cyan
    $ToDelete |
        Select-Object RelativePath, DestPath |
        Format-Table -AutoSize
} else {
    Write-Host "`n[INFO] No files to delete after exclusions." -ForegroundColor DarkGray
}

Write-Host "`n[INFO] Dry run complete. Use Sync-DevTrees.Apply.ps1 to apply changes." -ForegroundColor Yellow
exit 0
