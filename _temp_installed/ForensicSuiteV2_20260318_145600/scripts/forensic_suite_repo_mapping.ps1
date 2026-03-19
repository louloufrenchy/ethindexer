# =====================================================================
# forensic_suite_repo_mapping.ps1 (V9.3 — Corrected)
# Authoritative → Runtime-Only Mapping Generator
# =====================================================================

param(
    [string]$RepoA = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\forensic_suite_v2",
    [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2\forensic_suite_v2",
    [string]$OutCsv = "F:\tools\repo_mapping_suite.csv",
    [string]$ExclusionMap = "F:\tools\sync_dev_exclusions_v9.3.yaml"
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

Write-Host "=== Building Repo Mapping (V9.3 — Corrected) ===" -ForegroundColor Cyan
Write-Host "RepoA (authoritative suite): $RepoA" -ForegroundColor Gray
Write-Host "RepoB (runtime mirror suite): $RepoB" -ForegroundColor Gray
Write-Host "Output:                      $OutCsv" -ForegroundColor Gray

# ---------------------------------------------------------------------
# 1. LOAD EXCLUSION MAP
# ---------------------------------------------------------------------
$Patterns = @()

foreach ($line in (Get-Content $ExclusionMap)) {
    $trim = $line.Trim()
    if ($trim -like "- *") {
        $pat = $trim.Substring(1).Trim()
        if ($pat) { $Patterns += $pat }
    }
}

function Test-Excluded {
    param([string]$RelativePath)

    $p = $RelativePath.Replace("\","/").ToLower()

    foreach ($pat in $Patterns) {
        $norm = $pat.Replace("\","/").ToLower()

        # Directory patterns (prefix match)
        if ($norm.EndsWith("/")) {
            if ($p.StartsWith($norm)) { return $true }
        }
        # Wildcards
        elseif ($norm.Contains("*")) {
            if ($p -like $norm) { return $true }
        }
        # Exact or suffix match
        else {
            if ($p -eq $norm -or $p.EndsWith("/$norm") -or $p.EndsWith($norm)) {
                return $true
            }
        }
    }
    return $false
}

# ---------------------------------------------------------------------
# 2. ENUMERATE FILES
# ---------------------------------------------------------------------
$FilesA = Get-ChildItem -Path $RepoA -Recurse -File | ForEach-Object {
    $_.FullName.Replace($RepoA + "\", "")
}

$FilesB = Get-ChildItem -Path $RepoB -Recurse -File | ForEach-Object {
    $_.FullName.Replace($RepoB + "\", "")
}

$AllPaths = ($FilesA + $FilesB) | Sort-Object -Unique

# ---------------------------------------------------------------------
# 3. BUILD MAPPING
# ---------------------------------------------------------------------
$Rows = @()

foreach ($rel in $AllPaths) {

    if (Test-Excluded $rel) { continue }

    $src = Join-Path $RepoA $rel
    $dst = Join-Path $RepoB $rel

    $inA = Test-Path $src
    $inB = Test-Path $dst

    $hashA = $inA ? (Get-FileHash -Algorithm SHA256 -Path $src).Hash : $null
    $hashB = $inB ? (Get-FileHash -Algorithm SHA256 -Path $dst).Hash : $null

    $Rows += [PSCustomObject]@{
        RelativePath = $rel
        SourcePath   = $src
        DestPath     = $dst
        InRepoA      = $inA
        InRepoB      = $inB
        A_Hash       = $hashA
        B_Hash       = $hashB
        SourceRoot   = $RepoA
        DestRoot     = $RepoB
    }
}

$Rows | Sort-Object RelativePath | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

Write-Host "`n[SUCCESS] Repo mapping written to $OutCsv" -ForegroundColor Green
exit 0
