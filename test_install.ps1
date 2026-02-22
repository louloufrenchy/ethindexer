# 1. Setup Sandbox Environment
$testRoot = "C:\ForensicSuite_TestRun"
$payloadSrc = "installer_payload"

if (Test-Path $testRoot) { 
    Write-Host "Cleaning previous test directory..." -ForegroundColor Gray
    Remove-Item -Recurse -Force $testRoot 
}
New-Item -ItemType Directory -Path $testRoot

# 2. Stage Files (Simulate what Inno Setup does)
Write-Host "Staging files to $testRoot..." -ForegroundColor Cyan
Copy-Item -Path "$payloadSrc\*" -Destination $testRoot -Recurse -Force

# 3. Execute Bootstrap in a "Hider" Block
# We temporarily rename the known Python Program Files path to force the script 
# to use the bundled installer if it can't find a candidate.
Write-Host "Starting Bootstrap Test..." -ForegroundColor Green
Set-Location $testRoot

try {
    # Run the bootstrap script
    # We pass the installers explicitly to ensure it finds them in the local folder
    .\bootstrap.ps1 -PythonInstaller "python-3.14.2-amd64.exe" -WheelPath "forensic_suite_v2-0.1.2-py3-none-any.whl"
}
catch {
    Write-Host "Test Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# 4. Verify Results
Write-Host "`n=== Post-Test Verification ===" -ForegroundColor Cyan
$checks = @(
    "venv\Scripts\python.exe",
    "logs\gui.log",
    "ForensicSuite\ForensicSuite.exe"
)

foreach ($path in $checks) {
    if (Test-Path (Join-Path $testRoot $path)) {
        Write-Host "[PASS] Found: $path" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Missing: $path" -ForegroundColor Red
    }
}

Write-Host "`nReview the $testRoot folder to ensure the DB and Venv are initialized." -ForegroundColor White