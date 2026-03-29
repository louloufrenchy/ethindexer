<#
    Apply-RuntimePathPatch.ps1
    ---------------------------------------
    Moves embedded Python runtime OUTSIDE the package tree
    AND patches all scripts that reference the old path.

    Supports two modes:
      -Preview   : Show what will change, do NOT modify anything
      -Apply     : Apply the patch after showing the report

    Produces a full report:
      - filename
      - line number
      - line content
#>

param(
    [switch]$Preview,
    [switch]$Apply,
    [string]$Old = 'forensic_suite_v2\runtime\python',
    [string]$New = 'runtime\python'
)

Write-Host "=== Apply-RuntimePathPatch ===" -ForegroundColor Cyan
Write-Host "[INFO] Old path: $Old"
Write-Host "[INFO] New path: $New"
Write-Host ""

if (-not ($Preview -or $Apply)) {
    Write-Host "[ERROR] You must specify -Preview or -Apply." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# 1. MOVE THE RUNTIME FOLDER (Apply mode only)
# ------------------------------------------------------------
$oldRuntimePath = Join-Path $PSScriptRoot $Old
$newRuntimeRoot = Join-Path $PSScriptRoot "runtime"
$newRuntimePath = Join-Path $newRuntimeRoot "python"

if ($Apply) {
    if (Test-Path $oldRuntimePath) {
        if (-not (Test-Path $newRuntimeRoot)) {
            New-Item -ItemType Directory -Path $newRuntimeRoot | Out-Null
        }

        Write-Host "[MOVE] $Old -> $New" -ForegroundColor Yellow
        Move-Item $oldRuntimePath $newRuntimePath -Force
    } else {
        Write-Host "[SKIP] Old runtime folder not found (already removed or moved)" -ForegroundColor DarkYellow
    }
}

# ------------------------------------------------------------
# 2. SCAN FOR REFERENCES
# ------------------------------------------------------------
Write-Host ""
Write-Host "=== Scanning for references to patch ===" -ForegroundColor Cyan

$files = Get-ChildItem -Recurse -File -Include *.ps1,*.psm1,*.iss |
         Where-Object {
            $_.FullName -notmatch '\\installer_payload\\' -and
            $_.FullName -notmatch '\\_temp_installed\\' -and
            $_.Name -ne 'Apply-RuntimePathPatch.ps1'
         }

if (-not $files) {
    Write-Host "[OK] No script files found to scan." -ForegroundColor Green
    exit 0
}

$pattern = [regex]::Escape($Old)
$matches = Select-String -Path $files.FullName -Pattern $pattern

if (-not $matches) {
    Write-Host "[OK] No references found. Nothing to patch." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "=== REPORT: References detected ===" -ForegroundColor Yellow

$matches |
    Sort-Object Path, LineNumber |
    ForEach-Object {
        "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }

Write-Host ""
Write-Host "Total matches: $($matches.Count)"
Write-Host ""

if ($Preview) {
    Write-Host "[PREVIEW MODE] No changes applied." -ForegroundColor Cyan
    exit 0
}

# ------------------------------------------------------------
# 3. APPLY PATCHES
# ------------------------------------------------------------
Write-Host "=== Applying patch ===" -ForegroundColor Cyan

$filesToPatch = $matches | Select-Object -ExpandProperty Path -Unique

foreach ($file in $filesToPatch) {
    Write-Host "[PATCH] $file" -ForegroundColor Yellow
    (Get-Content $file) |
        ForEach-Object { $_ -replace $pattern, $New } |
        Set-Content $file -Encoding UTF8
}

Write-Host ""
Write-Host "[COMPLETE] Patch applied." -ForegroundColor Green

# ------------------------------------------------------------
# 4. VERIFY PATCH
# ------------------------------------------------------------
Write-Host ""
Write-Host "=== Verification scan ===" -ForegroundColor Cyan

$remaining = Select-String -Path $files.FullName -Pattern $pattern

if ($remaining) {
    Write-Host "[WARN] Some references remain:" -ForegroundColor Red
    $remaining |
        Sort-Object Path, LineNumber |
        ForEach-Object {
            "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
        }
} else {
    Write-Host "[OK] No remaining references. Patch fully applied." -ForegroundColor Green
}
