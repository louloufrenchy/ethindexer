# Auto-Test-Prep.ps1
# Full automation: Sync, Clean Cache, and Verify for Testing.

$primaryRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"
$testRepoPath = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2\forensic_suite_v2"

Write-Host "--- Starting Test Environment Preparation ---" -ForegroundColor Magenta

# STEP 1: Sync Logic
Write-Host "`n[1/5] Syncing Logic (Excluding Installer Payload)..." -ForegroundColor Yellow
& "$primaryRoot\Sync-DevTrees.ps1"

# STEP 2: Purge Python Cache
Write-Host "[2/5] Cleaning __pycache__ in Test Repo..." -ForegroundColor Yellow
Get-ChildItem -Path $testRepoPath -Recurse -Filter "__pycache__" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# STEP 3: Verify Modular Structure
Write-Host "[3/5] Verifying New Modular Layout..." -ForegroundColor Yellow
$modules = @("btc_indexer", "eth_indexer", "tron_indexer", "legacy", "core", "gui")
foreach ($m in $modules) {
    if (Test-Path "$testRepoPath\$m") {
        Write-Host "  [READY] $m" -ForegroundColor Green
    } else {
        Write-Warning "  [MISSING] $m - Check sync logs."
    }
}

# STEP 4: Check Primary Git State
Write-Host "[4/5] Current Primary Dev Branch Status:" -ForegroundColor Yellow
Push-Location $primaryRoot
git status --short
Pop-Location

# STEP 5: Quick Structure Preview
Write-Host "[5/5] Test Repo Structure Preview:" -ForegroundColor Yellow
Get-ChildItem $testRepoPath | Select-Object Name, LastWriteTime | Sort-Object LastWriteTime -Descending | Select-Object -First 10

Write-Host "`n--- Test Environment Ready ---" -ForegroundColor Magenta
