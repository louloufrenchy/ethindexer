# Sync-DevTrees.ps1
# Syncs code logic from Primary to Test repo, excluding installer bloat.

$source = "C:\development\forensic_tracer_installer_project_root\forensic_suite_v2"
$destination = "C:\development\forensic_suite_v2\forensic_suite_v2"

# Added 'installer_payload' and 'Output' to exclusion list to keep the test repo lean
$excludeDirs = @("venv", ".git", "__pycache__", "forensic_suite_v2.egg-info", "installer_payload", "Output", "dist", "build")
$excludeFiles = @(".env", "*.exe", "*.iss")

Write-Host ">>> Mirroring Logic to Test Repo..." -ForegroundColor Cyan

# /MIR ensures renamed folders (like btc_indexer) replace old ones
robocopy $source $destination /MIR /Z /XO /FFT /XD $excludeDirs /XF $excludeFiles /MT:16 /R:2 /W:5 /NP

if ($LASTEXITCODE -lt 8) {
    Write-Host "`n>>> Sync Complete. Test repo logic is now current." -ForegroundColor Green
} else {
    Write-Warning "Robocopy finished with exit code $LASTEXITCODE."
}