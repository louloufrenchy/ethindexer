# =========================================================
# FORENSIC SUITE - GUI/ASYNC ISSUE ISOLATION TOOLKIT
# =========================================================

Write-Host "=== Running GUI / asyncio isolation search ===" -ForegroundColor Cyan

# ---------------------------------------------------------
# 1. Focused source-only search
# ---------------------------------------------------------
Write-Host "`n[1] Searching source only (excluding .venv, payloads, build outputs)..." -ForegroundColor Yellow

Get-ChildItem -Recurse -Include *.py,*.ps1,*.psm1 -File |
    Where-Object {
        $_.FullName -notmatch '\\\.venv\\' -and
        $_.FullName -notmatch '\\installer_payload\\' -and
        $_.FullName -notmatch '\\Output\\' -and
        $_.FullName -notmatch '\\build\\' -and
        $_.FullName -notmatch '\\dist\\' -and
        $_.FullName -notmatch '\\python\\'
    } |
    Select-String "discover\(|_start_async|asyncio|Tk|tkinter|forensic_dashboard_gui|MultiChainDashboard" |
    Sort-Object Path, LineNumber |
    ForEach-Object {
        "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }

# ---------------------------------------------------------
# 2. Direct GUI bug search
# ---------------------------------------------------------
Write-Host "`n[2] Searching directly for likely GUI/async bug patterns..." -ForegroundColor Yellow

Get-ChildItem -Recurse -Include *.py -File |
    Where-Object {
        $_.FullName -notmatch '\\\.venv\\' -and
        $_.FullName -notmatch '\\installer_payload\\' -and
        $_.FullName -notmatch '\\Output\\' -and
        $_.FullName -notmatch '\\build\\' -and
        $_.FullName -notmatch '\\dist\\'
    } |
    Select-String "MultiChainDashboard|_start_async|asyncio.run|create_task|await |tkinter|mainloop|forensic_dashboard_gui" |
    Sort-Object Path, LineNumber |
    ForEach-Object {
        "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }

# ---------------------------------------------------------
# 3. Narrow search to dashboard/gui files only
# ---------------------------------------------------------
Write-Host "`n[3] Searching dashboard/gui files only..." -ForegroundColor Yellow

Get-ChildItem -Recurse -Include *.py -File |
    Where-Object {
        $_.FullName -notmatch '\\\.venv\\' -and
        $_.FullName -notmatch '\\installer_payload\\' -and
        $_.FullName -notmatch '\\Output\\' -and
        $_.FullName -notmatch '\\build\\' -and
        $_.FullName -notmatch '\\dist\\' -and
        $_.Name -match 'dashboard|gui'
    } |
    Select-String "_start_async|asyncio.run|create_task|await |tkinter|mainloop|MultiChainDashboard|forensic_dashboard_gui" |
    Sort-Object Path, LineNumber |
    ForEach-Object {
        "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }

# ---------------------------------------------------------
# 4. Git grep fallback (faster, if git is available)
# ---------------------------------------------------------
Write-Host "`n[4] Git grep fallback (if git is installed and repo is a git repo)..." -ForegroundColor Yellow

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    git grep -n -E "MultiChainDashboard|_start_async|asyncio.run|create_task|tkinter|mainloop|forensic_dashboard_gui|discover\(" 2>$null
}
else {
    Write-Host "git not found on PATH - skipping git grep fallback." -ForegroundColor DarkGray
}

Write-Host "`n=== GUI / asyncio isolation search complete ===" -ForegroundColor Green
