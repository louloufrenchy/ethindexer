# =====================================================================
# Hardened Installer Sandbox Test (V3)
# =====================================================================
$primaryRoot = "C:\development\forensic_tracer_installer_project_root"
$testRoot = "C:\ForensicSuite_TestRun"
$payloadSrc = Join-Path $primaryRoot "installer_payload"

# 1. Break the lock and purge
Set-Location $primaryRoot
if (Test-Path $testRoot) {
    Write-Host ">>> Purging stale sandbox..." -ForegroundColor Gray
    Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

# 2. Stage the payload
Write-Host ">>> Staging files to $testRoot..." -ForegroundColor Cyan
Copy-Item -Path "$payloadSrc\*" -Destination $testRoot -Recurse -Force

# 3. Drop secrets template
$secretRoot = "C:\forensic_secrets"
if (!(Test-Path $secretRoot)) { New-Item -ItemType Directory -Path $secretRoot | Out-Null }
$template = Join-Path $payloadSrc "dot_env.template"
$target = Join-Path $secretRoot "env.json"
if (!(Test-Path $target)) { Copy-Item $template $target }

# 4. Execute the Active Bootstrap
Write-Host ">>> Starting Hardened Bootstrap Test..." -ForegroundColor Green
Push-Location $testRoot
try {
    .\bootstrap.ps1
} finally {
    Pop-Location
}

# 5. Final Verification
Write-Host "`n=== Post-Test Verification ===" -ForegroundColor Cyan
$checks = @("venv\Scripts\python.exe", "logs", "dot_env.template")
foreach ($path in $checks) {
    if (Test-Path (Join-Path $testRoot $path)) {
        Write-Host "[PASS] Verified: $path" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Missing: $path" -ForegroundColor Red
    }
}
