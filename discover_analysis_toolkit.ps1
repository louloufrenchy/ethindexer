# =========================================================
# FORENSIC SUITE - DISCOVER() ANALYSIS TOOLKIT
# =========================================================

Write-Host "=== Running discover() analysis ===" -ForegroundColor Cyan

# ---------------------------------------------------------
# 1. Find all discover() occurrences
# ---------------------------------------------------------
Write-Host "`n[1] Searching for discover() calls..." -ForegroundColor Yellow

Get-ChildItem -Recurse -Include *.py,*.ps1,*.psm1,*.psd1 -File |
    Select-String "discover\(" |
    Sort-Object Path, LineNumber |
    ForEach-Object {
        "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }

# ---------------------------------------------------------
# 2. Find definitions of discover
# ---------------------------------------------------------
Write-Host "`n[2] Searching for discover definitions..." -ForegroundColor Yellow

Get-ChildItem -Recurse -Include *.py,*.ps1,*.psm1 -File |
    Select-String "def discover\(|function .*discover|class .*discover" |
    Sort-Object Path, LineNumber |
    ForEach-Object {
        "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }

# ---------------------------------------------------------
# 3. Find assignments/usages of discover()
# ---------------------------------------------------------
Write-Host "`n[3] Searching for discover() assignments/usages..." -ForegroundColor Yellow

Get-ChildItem -Recurse -Include *.py,*.ps1,*.psm1 -File |
    Select-String "\=\s*.*discover\(|discover\(.+\)\s*\|" |
    Sort-Object Path, LineNumber |
    ForEach-Object {
        "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }

# ---------------------------------------------------------
# 4. Focus on deployment / orchestration scripts
# ---------------------------------------------------------
Write-Host "`n[4] Searching discover() in deployment/orchestration paths..." -ForegroundColor Yellow

Get-ChildItem -Recurse -Include *.ps1,*.psm1 -File |
    Where-Object { $_.Name -match 'Forensic|Deploy|Release|Runtime|Validation' } |
    Select-String "discover\(" |
    Sort-Object Path, LineNumber |
    ForEach-Object {
        "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }

# ---------------------------------------------------------
# 5. Raw quick scan (fallback view)
# ---------------------------------------------------------
Write-Host "`n[5] Raw scan (quick view)..." -ForegroundColor Yellow

Get-ChildItem -Recurse -Include *.py,*.ps1,*.psm1,*.psd1 -File |
    Select-String "discover\("

Write-Host "`n=== Analysis Complete ===" -ForegroundColor Green
