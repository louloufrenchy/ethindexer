param(
    [string]$Host
)

Import-Module "$PSScriptRoot\Deploy-ForensicSuite.psm1" -Force

Write-Host "=== Validating host $Host ===" -ForegroundColor Cyan

# 1. Check SSH connectivity
$code = Invoke-Ssh -Host $Host -Command "hostname"
if ($code -ne 0) {
    Write-Host "SSH connectivity FAILED to $Host" -ForegroundColor Red
    exit 1
} else {
    Write-Host "SSH connectivity OK to $Host" -ForegroundColor Green
}

# 2. Check ForensicSuiteV2 install
$cmd = 'powershell -NoProfile -Command "if (Test-Path ''C:\Program Files\ForensicSuiteV2\venv\Scripts\python.exe'') { Write-Output ''OK'' } else { Write-Output ''MISSING'' }"'
$code = Invoke-Ssh -Host $Host -Command $cmd
if ($code -ne 0) {
    Write-Host "Failed to query ForensicSuiteV2 on $Host" -ForegroundColor Red
} else {
    Write-Host "ForensicSuiteV2 presence check executed (see SSH output above)." -ForegroundColor Green
}

# 3. Check Postgres + forensic DB
$cmd = 'powershell -NoProfile -Command "& ''C:\Program Files\PostgreSQL\18\bin\psql.exe'' -U postgres -d postgres -t -A -c ''SELECT datname FROM pg_database WHERE datname = ''''forensic'''';''"'
Invoke-Ssh -Host $Host -Command $cmd | ForEach-Object {
    if ($_.Trim() -eq "forensic") {
        Write-Host "forensic DB exists on $Host" -ForegroundColor Green
    } else {
        Write-Host "forensic DB MISSING on $Host" -ForegroundColor Red
    }
}

Write-Host "Validation complete for $Host" -ForegroundColor Cyan
