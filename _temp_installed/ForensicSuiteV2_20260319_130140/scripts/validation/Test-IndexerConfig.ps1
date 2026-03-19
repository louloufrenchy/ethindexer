param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [Parameter(Mandatory=$true)][string]$EnvPath
)

if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath" }
if (-not (Test-Path $EnvPath))   { throw "Env not found: $EnvPath" }

$envVars = @{}
Get-Content $EnvPath | ForEach-Object {
    if ($_ -match "^\s*#") { return }
    if ($_ -match "^\s*$") { return }
    $parts = $_.Split("=",2)
    if ($parts.Count -eq 2) {
        $envVars[$parts[0]] = $parts[1]
    }
}

$configRaw = Get-Content $ConfigPath -Raw

$missing = @()
$configRaw -split "`n" | ForEach-Object {
    if ($_ -match "\$\{([^}]+)\}") {
        $var = $Matches[1]
        if (-not $envVars.ContainsKey($var)) {
            $missing += $var
        }
    }
}

if ($missing.Count -gt 0) {
    Write-Host "[FAIL] Missing env vars for config:" -ForegroundColor Red
    $missing | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "[OK] All referenced env vars are present in .env" -ForegroundColor Green
