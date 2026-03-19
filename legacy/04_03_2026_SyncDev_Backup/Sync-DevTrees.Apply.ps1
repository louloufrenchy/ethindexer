<#
    Sync‑DevTrees.Apply.ps1
    V9.3.2 — Strict Allow‑List Edition
    Applies authoritative → runtime‑only mirror into TargetRoot.
#>

param(
    [string]$MappingCsv,
    [string]$TargetRoot
)

$ErrorActionPreference = "Stop"

Write-Host "=== Sync‑DevTrees APPLY (V9.3) ===" -ForegroundColor Cyan
Write-Host "Repo A (authoritative root): $($Global:PrimaryRoot)" -ForegroundColor Gray
Write-Host "Repo B (mirror root)      : $TargetRoot" -ForegroundColor Gray

# ---------------------------------------------------------------------
# 0. Load mapping
# ---------------------------------------------------------------------
if (!(Test-Path $MappingCsv)) {
    Write-Host "[ERROR] Mapping CSV not found: $MappingCsv" -ForegroundColor Red
    exit 1
}

$rows = Import-Csv $MappingCsv
if ($rows.Count -eq 0) {
    Write-Host "[ERROR] Mapping CSV is empty." -ForegroundColor Red
    exit 2
}

# ---------------------------------------------------------------------
# 1. Strict allow‑list for runtime‑safe content
# ---------------------------------------------------------------------
$AllowedTopLevel = @(
    "forensic_suite_v2",
    "dashboards",
    "scripts",
    "wheel",
    "pyproject.toml",
    "indexers",
    "grafana"
)

$AllowedScripts = @(
    "install_services.ps1",
    "windows_orchestrator_service.ps1",
    "operator_console.ps1",
    "healthcheck.ps1",
    "healthcheck_core.py"
)

function Is‑AllowedPath {
    param([string]$RelPath)

    # Normalize slashes
    $p = $RelPath -replace "/", "\"

    # Allowed top‑level folders
    foreach ($root in $AllowedTopLevel) {
        if ($p -like "$root\*") { return $true }
    }

    # Allowed scripts
    foreach ($s in $AllowedScripts) {
        if ($p -eq "scripts\$s") { return $true }
    }

    # Allowed wheel
    if ($p -like "wheel\*.whl") { return $true }

    # Allowed bootstrap/templates (installer payload only)
    if ($p -in @("bootstrap.ps1", "env.template.json", "dot_env.template")) {
        return $true
    }

    return $false
}

# ---------------------------------------------------------------------
# 2. Apply mapping with strict allow‑list
# ---------------------------------------------------------------------
$Included = @()
$Excluded = @()

foreach ($row in $rows) {
    if (Is‑AllowedPath $row.RelativePath) {
        $Included += $row
    } else {
        $Excluded += $row
    }
}

Write-Host ""
Write-Host "[INFO] After strict allow‑list filtering:" -ForegroundColor Cyan
Write-Host "  Included rows : $($Included.Count)"
Write-Host "  Excluded rows : $($Excluded.Count)"

# ---------------------------------------------------------------------
# 3. Copy included files into TargetRoot
# ---------------------------------------------------------------------
foreach ($row in $Included) {
    $src = $row.SourcePath
    $dst = Join-Path $TargetRoot $row.RelativePath

    $dstDir = Split-Path $dst -Parent
    if (!(Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    Write-Host "[COPY] $($row.RelativePath)" -ForegroundColor Green
    Copy-Item $src $dst -Force
}

# ---------------------------------------------------------------------
# 4. Final summary
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "[SUCCESS] RepoB mirror synchronized with RepoA (strict allow‑list enforced)." -ForegroundColor Green
Write-Host "         Effective destination root: $TargetRoot" -ForegroundColor Gray
Write-Host "         Run Sync‑DevTrees.Validate.ps1 to verify integrity." -ForegroundColor Gray

exit 0
