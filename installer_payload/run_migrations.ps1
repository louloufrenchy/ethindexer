$pgBin = "C:\Program Files\PostgreSQL\18\bin"
$psql  = Join-Path $pgBin "psql.exe"
$env:PGPASSWORD = "Str0ngPassw0rd2025"

$migrationsPath = "C:\Program Files\ForensicSuiteV2\db\migrations"

Write-Host "=== Running DB migrations against 'forensic' ===" -ForegroundColor Cyan

if (-not (Test-Path $migrationsPath)) {
    Write-Host "Migrations folder not found: $migrationsPath" -ForegroundColor Red
    exit 1
}

$files = Get-ChildItem $migrationsPath -Filter "*.sql" | Sort-Object Name

if ($files.Count -eq 0) {
    Write-Host "No migration files found." -ForegroundColor Yellow
    exit 0
}

foreach ($file in $files) {
    Write-Host ("Applying migration: {0}" -f $file.Name) -ForegroundColor Yellow
    & $psql -U postgres -d forensic -f $file.FullName
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("Migration failed: {0}" -f $file.Name) -ForegroundColor Red
        exit 1
    }
}

Write-Host "All migrations applied successfully." -ForegroundColor Green
