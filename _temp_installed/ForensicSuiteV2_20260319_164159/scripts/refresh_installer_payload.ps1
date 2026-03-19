<# =====================================================================
   refresh_installer_payload.ps1 (V9.3.4 — Strict Allow-List, Authoritative)
   - Rebuilds installer_payload from repo sources
   - Ensures scripts are in sync, runtime tree is clean, and no dev junk
   - Copies runtime requirements, not build requirements
   ===================================================================== #>

$ErrorActionPreference = "Stop"

# scripts\refresh_installer_payload.ps1  ->  repo root is its parent
$ScriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = Split-Path -Parent $ScriptRoot
$PayloadRoot = Join-Path $RepoRoot "installer_payload"

$PythonRuntimeRoot = Join-Path $RepoRoot "forensic_suite_v2\runtime\python"
$PayloadPythonRoot = Join-Path $PayloadRoot "python"

Write-Host "=== Refreshing Installer Payload (Strict Allow-List, Authoritative) ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot" -ForegroundColor Gray
Write-Host "Payload   : $PayloadRoot" -ForegroundColor Gray

if (-not (Test-Path $PayloadRoot)) {
    New-Item -ItemType Directory -Path $PayloadRoot | Out-Null
}

function Remove-IfExists {
    param([string]$Path)
    if (Test-Path $Path) {
        Write-Host "[PRUNE] $Path" -ForegroundColor Yellow
        Remove-Item $Path -Recurse -Force
    }
}

# --- Python runtime ---
if (-not (Test-Path $PythonRuntimeRoot)) {
    throw "Python runtime not found at $PythonRuntimeRoot"
}

New-Item -ItemType Directory -Path $PayloadPythonRoot -Force | Out-Null
Copy-Item -Recurse -Force "$PythonRuntimeRoot\*" "$PayloadPythonRoot\"

# ---------------------------------------------------------------------
# 1. Root payload files (bootstrap + templates + runtime requirements)
# ---------------------------------------------------------------------

$rootFiles = @(
    "bootstrap.ps1",
    "env.template.json",
    "dot_env.template"
)

foreach ($f in $rootFiles) {
    $src = Join-Path $RepoRoot $f
    $dst = Join-Path $PayloadRoot $f

    if (Test-Path $src) {
        Write-Host "[SYNC] $f" -ForegroundColor Cyan
        Copy-Item $src $dst -Force
    } else {
        Write-Host "[WARN] Missing source root file: $src" -ForegroundColor Yellow
    }
}

$RuntimeRequirementsSrc = Join-Path $RepoRoot "forensic_suite_v2\requirements.runtime.txt"
$RuntimeRequirementsDst = Join-Path $PayloadRoot "requirements.txt"

if (Test-Path $RuntimeRequirementsSrc) {
    Write-Host "[SYNC] runtime requirements -> installer_payload\requirements.txt" -ForegroundColor Cyan
    Copy-Item $RuntimeRequirementsSrc $RuntimeRequirementsDst -Force
} else {
    Write-Host "[WARN] Missing runtime requirements file: $RuntimeRequirementsSrc" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 2. Scripts: mirror repo scripts -> payload\scripts (full, no filtering)
# ---------------------------------------------------------------------

$SrcScripts = Join-Path $RepoRoot "scripts"
$DstScripts = Join-Path $PayloadRoot "scripts"

Remove-IfExists $DstScripts

if (Test-Path $SrcScripts) {
    Write-Host "[SYNC] scripts -> installer_payload\scripts" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $DstScripts | Out-Null
    Copy-Item "$SrcScripts\*" $DstScripts -Recurse -Force
} else {
    Write-Host "[WARN] Source scripts folder missing: $SrcScripts" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 3. Wheel: keep only wheel\forensic_suite_v2-*.whl
# ---------------------------------------------------------------------

$WheelSrcDir = Join-Path $RepoRoot "dist"
$WheelDstDir = Join-Path $PayloadRoot "wheel"

Remove-IfExists $WheelDstDir
New-Item -ItemType Directory -Path $WheelDstDir | Out-Null

$latestWheel = Get-ChildItem $WheelSrcDir -Filter "forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending |
               Select-Object -First 1

if ($latestWheel) {
    Write-Host "[SYNC] Wheel -> installer_payload\wheel\$($latestWheel.Name)" -ForegroundColor Cyan
    Copy-Item $latestWheel.FullName (Join-Path $WheelDstDir $latestWheel.Name) -Force
} else {
    Write-Host "[WARN] No wheel found in dist\forensic_suite_v2-*.whl" -ForegroundColor Yellow
}

Get-ChildItem $PayloadRoot -Filter "forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host "[PRUNE] Duplicate wheel at payload root: $($_.FullName)" -ForegroundColor Yellow
        Remove-Item $_.FullName -Force
    }

# ---------------------------------------------------------------------
# 4. forensic_suite_v2 runtime tree (strict allow-list)
# ---------------------------------------------------------------------

$SrcSuite = Join-Path $RepoRoot "forensic_suite_v2"
$DstSuite = Join-Path $PayloadRoot "forensic_suite_v2"

Remove-IfExists $DstSuite

if (Test-Path $SrcSuite) {
    Write-Host "[SYNC] forensic_suite_v2 runtime tree -> installer_payload\forensic_suite_v2" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $DstSuite | Out-Null

    Copy-Item "$SrcSuite\*" $DstSuite -Recurse -Force

    Remove-IfExists (Join-Path $DstSuite "logs")
    Remove-IfExists (Join-Path $DstSuite "tests")
    Remove-IfExists (Join-Path $DstSuite "tools")
    Remove-IfExists (Join-Path $DstSuite "plugins")
    # Remove-IfExists (Join-Path $DstSuite "gui")

    Get-ChildItem $DstSuite -Recurse -Directory -Filter "_pycache_" -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Host "[PRUNE] _pycache_ -> $($_.FullName)" -ForegroundColor Yellow
            Remove-IfExists $_.FullName
        }
} else {
    Write-Host "[WARN] Source forensic_suite_v2 missing: $SrcSuite" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 4b. Ensure runtime scripts are included
# ---------------------------------------------------------------------
$SrcRuntimeScripts = Join-Path $SrcSuite "scripts"
$DstRuntimeScripts = Join-Path $DstSuite "scripts"

if (Test-Path $SrcRuntimeScripts) {
    Write-Host "[SYNC] forensic_suite_v2 runtime scripts -> installer_payload\forensic_suite_v2\scripts" -ForegroundColor Cyan
    Copy-Item "$SrcRuntimeScripts\*" $DstRuntimeScripts -Recurse -Force
} else {
    Write-Host "[WARN] Missing runtime scripts folder: $SrcRuntimeScripts" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 5. Remove root dashboards folder (not needed in payload)
# ---------------------------------------------------------------------

Remove-IfExists (Join-Path $PayloadRoot "dashboards")

Write-Host "[OK] Installer payload refreshed with strict runtime-only, authoritative rules." -ForegroundColor Green
