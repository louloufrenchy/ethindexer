# =====================================================================
# Hardened Installer Sandbox Test (V5 - True Production Mirror)
# =====================================================================
$primaryRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"
$testRoot = "C:\forensic_suite_v2_green"
$payloadSrc = Join-Path $primaryRoot "installer_payload"
$symlink = "C:\forensic_suite_v2"
$validator = "F:\tools\Validate-ForensicSlot.ps1"   # adjust if needed

# 1. Environment Hardening (Prevent Error 1053)
Write-Host ">>> Extending Windows Service Timeout..." -ForegroundColor Yellow
$regPath = "HKLM\SYSTEM\CurrentControlSet\Control"
reg add $regPath /v ServicesPipeTimeout /t REG_DWORD /d 60000 /f | Out-Null

# 2. Break the lock and purge GREEN slot
if (Test-Path $testRoot) {
    Write-Host ">>> Stopping services and purging stale slot..." -ForegroundColor Gray
    Stop-Service btc_indexer  -Force -ErrorAction SilentlyContinue
    Stop-Service eth_indexer  -Force -ErrorAction SilentlyContinue
    Stop-Service tron_indexer -Force -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

# 3. Stage the payload
Write-Host ">>> Staging files to $testRoot..." -ForegroundColor Cyan
Copy-Item -Path "$payloadSrc\*" -Destination $testRoot -Recurse -Force

# 4. Provision Secrets (Production Schema)
$secretRoot = "F:\forensic_secrets"
if (!(Test-Path $secretRoot)) { New-Item -ItemType Directory -Path $secretRoot | Out-Null }
$realSecret = Join-Path $primaryRoot "env.json"
$target = Join-Path $secretRoot "env.json"

if (Test-Path $realSecret) {
    Copy-Item $realSecret $target -Force
    Write-Host "[OK] Real secrets provisioned for database sync." -ForegroundColor Green
} else {
    Write-Host "[WARN] Using template secrets. Service will likely crash." -ForegroundColor Red
    Copy-Item (Join-Path $payloadSrc "env.template.json") $target -Force
}

# 5. Execute the Active Bootstrap (installs venv + registers services to symlink)
Write-Host ">>> Starting Hardened Bootstrap Test..." -ForegroundColor Green
Push-Location $testRoot
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    .\bootstrap.ps1
} finally {
    Pop-Location
}

# 6. Final Verification (Authoritative Tree Check - slot level)
Write-Host "`n=== Authoritative Tree Verification ===" -ForegroundColor Cyan
$checks = @(
    "venv\Scripts\python.exe",
    "venv\Scripts\forensic-suite-v2-run-tron-indexer.exe",
    "config\tracer_v2.yaml"
)
foreach ($path in $checks) {
    if (Test-Path (Join-Path $testRoot $path)) {
        Write-Host "[PASS] Verified: $path" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Missing authoritative path: $path" -ForegroundColor Red
    }
}

# 7. Slot Validation (inactive GREEN, before activation)
if (Test-Path $validator) {
    Write-Host "`n>>> Validating GREEN slot..." -ForegroundColor Cyan
    & $validator
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Slot validation failed. Aborting Test-Install." -ForegroundColor Red
        return
    }
} else {
    Write-Host "[WARN] Validator not found at $validator. Skipping slot validation." -ForegroundColor DarkYellow
}

# 8. Switch symlink to GREEN
Write-Host "`n>>> Switching symlink to GREEN..." -ForegroundColor Cyan
if (Test-Path $symlink) { Remove-Item $symlink -Force }
New-Item -ItemType SymbolicLink -Path $symlink -Target $testRoot | Out-Null
Write-Host "[OK] Symlink now points to GREEN: $testRoot" -ForegroundColor Green

# 9. Start services (now pointing via symlink)
Write-Host "`n>>> Starting indexer services..." -ForegroundColor Cyan
$services = @("btc_indexer", "eth_indexer", "tron_indexer")
foreach ($svc in $services) {
    try {
        Start-Service $svc -ErrorAction Stop
        Write-Host "[OK] Started $svc" -ForegroundColor Green
    } catch {
        Write-Host ("[FAIL] Failed to start {0}: {1}" -f $svc, $_) -ForegroundColor Red
    }
}

# 10. SCM Handshake / Health Check
Write-Host "`n>>> Verifying Service Handshake..." -ForegroundColor Cyan
foreach ($svc in $services) {
    $status = Get-Service $svc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status
    if ($status -eq "Running") {
        Write-Host "[PASS] $svc is RUNNING." -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $svc is $status. Check Event Viewer." -ForegroundColor Red
    }
}
