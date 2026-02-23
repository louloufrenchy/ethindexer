param(
    [string]$Host,
    [string[]]$Roles,
    [switch]$All
)

Import-Module "$PSScriptRoot\Deploy-ForensicSuite.psm1" -Force

# Load manifest
$manifestPath = Join-Path $PSScriptRoot "deployment_manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Host "ERROR: deployment_manifest.json not found at $manifestPath" -ForegroundColor Red
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

# -------------------------------
# Determine target hosts
# -------------------------------
$targets = @()

if ($Host) {
    $entry = $manifest.hosts | Where-Object { $_.ip -eq $Host }
    if (-not $entry) {
        Write-Host "ERROR: Host $Host not found in manifest." -ForegroundColor Red
        exit 1
    }
    $targets = @($entry)
} elseif ($Roles) {
    $targets = $manifest.hosts | Where-Object {
        $_.roles | Where-Object { $Roles -contains $_ }
    }
    if (-not $targets) {
        Write-Host "ERROR: No hosts match roles: $($Roles -join ', ')" -ForegroundColor Red
        exit 1
    }
} elseif ($All) {
    $targets = $manifest.hosts
} else {
    Write-Host "ERROR: Specify -Host, -Roles, or -All." -ForegroundColor Red
    exit 1
}

Write-Host "=== BLUE/GREEN ROLLBACK ===" -ForegroundColor Yellow

# -------------------------------
# Rollback logic per host
# -------------------------------
foreach ($t in $targets) {
    $ip = $t.ip
    Write-Host ""
    Write-Host ">>> Host: $ip" -ForegroundColor Cyan

    # Detect active slot
    $detectCmd = @'
$cur = "C:\Program Files\ForensicSuiteV2\current"
if (-not (Test-Path $cur)) { Write-Output "NONE"; exit }

$target = (Get-Item $cur).Target
if ($target -match "blue") { Write-Output "BLUE" }
elseif ($target -match "green") { Write-Output "GREEN" }
else { Write-Output "UNKNOWN" }
'@

    $active = Invoke-Ssh -Host $ip -Command "pwsh -NoProfile -Command `$($detectCmd)`"

    if (-not $active) {
        Write-Host "ERROR: Could not detect active slot on $ip" -ForegroundColor Red
        continue
    }

    $slot = $active.Trim()
    Write-Host "Active slot: $slot" -ForegroundColor Yellow

    if ($slot -eq "NONE" -or $slot -eq "UNKNOWN") {
        Write-Host "Skipping $ip — no valid blue/green slot detected." -ForegroundColor DarkGray
        continue
    }

    # Determine paths
    $bluePath  = "C:\Program Files\ForensicSuiteV2\blue"
    $greenPath = "C:\Program Files\ForensicSuiteV2\green"
    $current   = "C:\Program Files\ForensicSuiteV2\current"

    if ($slot -eq "BLUE") {
        $removePath = $bluePath
        $fallback   = $greenPath
    } else {
        $removePath = $greenPath
        $fallback   = $bluePath
    }

    # Remove active slot
    $removeCmd = "pwsh -NoProfile -Command `"if (Test-Path '$removePath') { Remove-Item -Recurse -Force '$removePath' }`""
    Invoke-Ssh -Host $ip -Command $removeCmd | Out-Null
    Write-Host "Removed active slot: $removePath" -ForegroundColor Green

    # Re-point symlink
    $linkCmd = @"
    pwsh -NoProfile -Command "
if (Test-Path '$current') { Remove-Item -Force '$current' }
if (Test-Path '$fallback') {
    New-Item -ItemType SymbolicLink -Path '$current' -Target '$fallback' | Out-Null
}
"
    "@

    Invoke-Ssh -Host $ip -Command $linkCmd | Out-Null
    Write-Host "Re-pointed 'current' symlink to: $fallback" -ForegroundColor Green

    # Cleanup installer
    Cleanup-RemoteInstaller -Host $ip | Out-Null
    Write-Host "Installer cleanup complete." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "=== Blue/Green rollback complete ===" -ForegroundColor Green
