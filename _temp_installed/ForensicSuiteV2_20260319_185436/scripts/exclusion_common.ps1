# =====================================================================
# exclusion_common.ps1 (V9.3)
# Shared exclusion engine for all exclusion tools
# =====================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$ExclusionMap
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $ExclusionMap)) {
    throw "Exclusion map not found: $ExclusionMap"
}

# ------------------------------------------------------------
# LOAD YAML-LITE PATTERNS
# ------------------------------------------------------------
$RawLines = Get-Content $ExclusionMap
$Global:ExclusionPatterns = @()

foreach ($line in $RawLines) {
    $trim = $line.Trim()
    if ($trim -like "- *") {
        $pat = $trim.Substring(1).Trim()
        if ($pat) { $Global:ExclusionPatterns += $pat }
    }
}

# ------------------------------------------------------------
# NORMALIZED MATCH ENGINE
# ------------------------------------------------------------
function Test-Excluded {
    param([string]$RelativePath)

    $p = $RelativePath.Replace("\","/").ToLower()

    foreach ($pat in $Global:ExclusionPatterns) {
        $norm = $pat.Replace("\","/").ToLower()

        # Directory-style patterns
        if ($norm.EndsWith("/")) {
            if ($p -like "$norm*") { return $true }
        }
        # Wildcards
        elseif ($norm -like "*`**" -or $norm -like "*`**/*" -or $norm -like "*`*.*") {
            if ($p -like $norm) { return $true }
        }
        # Simple prefix/suffix
        else {
            if ($p -like $norm -or $p.EndsWith($norm)) { return $true }
        }
    }

    return $false
}

Write-Output "[COMMON] Loaded $($Global:ExclusionPatterns.Count) exclusion patterns."
