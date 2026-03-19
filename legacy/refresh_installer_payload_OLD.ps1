param(
    [string]$ProjectRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)

Write-Host "=== Refreshing Installer Payload (Authoritative Repo A) ===" -ForegroundColor Cyan

$payloadRoot = Join-Path $ProjectRoot "installer_payload"
$distDir     = Join-Path $ProjectRoot "dist"

if (-not (Test-Path $distDir)) {
    Write-Host "[ERROR] dist folder not found: $distDir" -ForegroundColor Red
    exit 1
}

# Ensure payload root exists and is clean (but keep existing installer exe if present)
if (-not (Test-Path $payloadRoot)) {
    New-Item -ItemType Directory -Path $payloadRoot | Out-Null
} else {
    Get-ChildItem $payloadRoot -Recurse -Force |
        Where-Object { $_.Name -notlike "ForensicSuiteV2-Setup.exe" } |
        Remove-Item -Recurse -Force
}

# ---------------------------------------------------------------------------
# 1. Copy latest wheel into installer_payload\wheel
# ---------------------------------------------------------------------------
$wheel = Get-ChildItem $distDir -Filter "forensic_suite_v2-*.whl" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $wheel) {
    Write-Host "[ERROR] No wheel found in $distDir" -ForegroundColor Red
    exit 1
}

$wheelDir = Join-Path $payloadRoot "wheel"
New-Item -ItemType Directory -Force -Path $wheelDir | Out-Null
Copy-Item -Path $wheel.FullName -Destination $wheelDir -Force

# ---------------------------------------------------------------------------
# 2. Copy authoritative tree from Repo A into payload
#    (mirror target-machine layout)
# ---------------------------------------------------------------------------

# Root-level files
Copy-Item -Path (Join-Path $ProjectRoot "bootstrap.ps1")     -Destination $payloadRoot -Force
Copy-Item -Path (Join-Path $ProjectRoot "env.template.json") -Destination $payloadRoot -Force
Copy-Item -Path (Join-Path $ProjectRoot "dot_env.template")  -Destination $payloadRoot -Force

# Core folders that must exist on target machine
$foldersToMirror = @(
    "config",
    "dashboards",
    "db",
    "scripts",
    "tools",
    "plugins",
    "gui",
    "forensic_suite_v2"
)

foreach ($folder in $foldersToMirror) {
    $src = Join-Path $ProjectRoot $folder
    $dst = Join-Path $payloadRoot  $folder

    if (-not (Test-Path $src)) {
        Write-Host "[WARN] Authoritative folder missing in Repo A: $src" -ForegroundColor Yellow
        continue
    }

    Write-Host "Mirroring $folder -> installer_payload\$folder"
    Copy-Item -Path $src -Destination $dst -Recurse -Force
}

Write-Host "Installer payload refresh complete." -ForegroundColor Green
