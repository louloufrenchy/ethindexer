param(
    [string]$ProjectRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path),
    [string[]]$RemoteHosts
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Test-ForensicWheelIntegrity ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Resolve wheel locations
# ---------------------------------------------------------------------------

$payloadWheel = Get-ChildItem -Path (Join-Path $ProjectRoot 'installer_payload\wheel\*.whl') -ErrorAction Stop | Select-Object -First 1
$tempWheel    = Get-ChildItem -Path (Join-Path $ProjectRoot '_temp_installed\ForensicSuiteV2_*\\wheel\\*.whl') -ErrorAction Stop | Select-Object -First 1

Write-Host "[INFO] Payload wheel: $($payloadWheel.FullName)"
Write-Host "[INFO] Temp-installed wheel: $($tempWheel.FullName)"

# Optional: Repo A dist wheel (if present)
$repoWheel = Get-ChildItem -Path (Join-Path $ProjectRoot '..\forensic_suite_v2\dist\*.whl') -ErrorAction SilentlyContinue | Select-Object -First 1
if ($repoWheel) {
    Write-Host "[INFO] Repo wheel: $($repoWheel.FullName)"
}

# ---------------------------------------------------------------------------
# Compute hashes
# ---------------------------------------------------------------------------

function Get-WheelHash {
    param([string]$Path)
    return (Get-FileHash $Path -Algorithm SHA256).Hash
}

$hashPayload = Get-WheelHash $payloadWheel.FullName
$hashTemp    = Get-WheelHash $tempWheel.FullName
$hashRepo    = $null

if ($repoWheel) {
    $hashRepo = Get-WheelHash $repoWheel.FullName
}

Write-Host ""
Write-Host "Payload Hash:      $hashPayload"
Write-Host "Temp-Installed:    $hashTemp"
if ($hashRepo) {
    Write-Host "Repo Dist Hash:    $hashRepo"
}

# ---------------------------------------------------------------------------
# Compare local hashes
# ---------------------------------------------------------------------------

if ($hashPayload -eq $hashTemp) {
    Write-Host "[OK] Payload wheel matches temp-installed wheel." -ForegroundColor Green
} else {
    Write-Host "[FAIL] Payload wheel does NOT match temp-installed wheel." -ForegroundColor Red
    exit 1
}

if ($hashRepo) {
    if ($hashPayload -eq $hashRepo) {
        Write-Host "[OK] Payload wheel matches Repo dist wheel." -ForegroundColor Green
    } else {
        Write-Host "[WARN] Payload wheel does NOT match Repo dist wheel." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Remote host validation (optional)
# ---------------------------------------------------------------------------

if ($RemoteHosts) {
    foreach ($host in $RemoteHosts) {
        Write-Host ""
        Write-Host ">>> Checking remote host $host ..." -ForegroundColor Cyan

        $remoteWheel = Invoke-RemotePS -Host $host -Script @"
Get-ChildItem -Path 'C:\forensic_suite_v2_green\wheel\*.whl' | Select-Object -First 1
"@

        if (-not $remoteWheel) {
            Write-Host "[FAIL] No wheel found on remote host $host." -ForegroundColor Red
            continue
        }

        $remoteHash = Invoke-RemotePS -Host $host -Script @"
(Get-FileHash '$($remoteWheel.FullName)' -Algorithm SHA256).Hash
"@

        Write-Host "Remote Hash ($host): $remoteHash"

        if ($remoteHash -eq $hashPayload) {
            Write-Host "[OK] Remote host $host wheel matches payload." -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Remote host $host wheel does NOT match payload." -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "[COMPLETE] Wheel integrity validation finished." -ForegroundColor Cyan
