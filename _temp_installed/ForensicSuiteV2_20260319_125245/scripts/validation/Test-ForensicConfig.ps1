param(
    [string]$SecretsRoot = 'C:\forensic_secrets'
)

$envPath = Join-Path $SecretsRoot '.env'
if (-not (Test-Path $envPath)) {
    throw "[CONFIG] .env not found at $envPath"
}

$lines = Get-Content $envPath | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '=' }

$bad = @()
foreach ($line in $lines) {
    $name, $value = $line.Split('=', 2)
    $name  = $name.Trim()
    $value = $value.Trim()

    if (-not $name) { continue }

    if ($value -eq '' -or $value -eq 'REPLACE_ME' -or $value -like '*REPLACE_ME*') {
        $bad += $name
    }
}

if ($bad.Count -gt 0) {
    throw "[CONFIG] Invalid or placeholder values in .env: $($bad -join ', ')"
}

Write-Host "[OK] Secrets configuration validated." -ForegroundColor Green
