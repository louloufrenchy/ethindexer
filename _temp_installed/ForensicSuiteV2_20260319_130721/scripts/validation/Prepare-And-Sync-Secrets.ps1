param(
    [Parameter(Mandatory = $true)]
    [string[]]$Hosts,

    [string]$SecretsRoot = 'C:\forensic_secrets'
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$exportScript = Join-Path $scriptRoot 'Export-EnvFromJson.ps1'
$localConfigValidator = Join-Path $scriptRoot 'Test-ForensicConfig.ps1'
$secretsModule = Join-Path $scriptRoot 'ForensicSecrets.psm1'

Write-Host "=== Prepare and Sync Secrets ===" -ForegroundColor Cyan
Write-Host "[INFO] Secrets root: $SecretsRoot"

if (-not (Test-Path $exportScript)) {
    throw "Export script not found: $exportScript"
}

if (-not (Test-Path $localConfigValidator)) {
    throw "Local config validator not found: $localConfigValidator"
}

if (-not (Test-Path $secretsModule)) {
    throw "Secrets module not found: $secretsModule"
}

# 1. Regenerate .env from env.json locally
Write-Host ">>> Regenerating .env from env.json locally..."
try {
    & $exportScript -SecretsRoot $SecretsRoot
}
catch {
    throw "Local Export-EnvFromJson.ps1 failed: $($_.Exception.Message)"
}
Write-Host "[OK] .env regenerated."

# 2. Validate local .env / secrets config
Write-Host ">>> Validating local secrets configuration..."
try {
    & $localConfigValidator -SecretsRoot $SecretsRoot
}
catch {
    throw "Local Test-ForensicConfig.ps1 failed: $($_.Exception.Message)"
}
Write-Host "[OK] Local secrets configuration validated."

# 3. Import helper module
Import-Module $secretsModule -Force

foreach ($targetHost in $Hosts) {
    Write-Host ">>> Syncing secrets to $targetHost ..."

    Sync-ForensicSecretsRemote `
        -TargetHost $targetHost `
        -SourceSecretsRoot $SecretsRoot

    Write-Host "[OK] Secrets synced to $targetHost."

    Write-Host ">>> Regenerating remote .env on $targetHost ..."

    $exportContent = Get-Content $exportScript -Raw
    if ([string]::IsNullOrWhiteSpace($exportContent)) {
        throw "Export script content is empty: $exportScript"
    }

    $exportBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($exportContent))

    $remoteExportScript = @"
`$ErrorActionPreference = 'Stop'

if (-not (Test-Path 'C:\Temp')) {
    New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null
}

`$bytes = [Convert]::FromBase64String('$exportBase64')
$text  = [Text.Encoding]::UTF8.GetString($bytes)
`$tempScript = 'C:\Temp\Export-EnvFromJson.ps1'

Set-Content -Path `$tempScript -Value `$text -Encoding UTF8

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$tempScript -SecretsRoot 'C:\forensic_secrets'
    if (`$LASTEXITCODE -ne 0) {
        throw ('Remote Export-EnvFromJson.ps1 failed with exit code {0}' -f `$LASTEXITCODE)
    }
}
finally {
    Remove-Item `$tempScript -Force -ErrorAction SilentlyContinue
}
"@

    Invoke-RemotePS -Host $targetHost -Script $remoteExportScript | Out-Null

    Write-Host "[OK] Remote .env regenerated on $targetHost."

    Write-Host ">>> Validating secrets on $targetHost ..."

    $validatorContent = Get-Content $localConfigValidator -Raw
    if ([string]::IsNullOrWhiteSpace($validatorContent)) {
        throw "Validator script content is empty: $localConfigValidator"
    }

    $validatorBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($validatorContent))

    $validatorScript = @"
`$ErrorActionPreference = 'Stop'

if (-not (Test-Path 'C:\Temp')) {
    New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null
}

`$bytes = [Convert]::FromBase64String('$validatorBase64')
$text  = [Text.Encoding]::UTF8.GetString($bytes)
`$tempScript = 'C:\Temp\Test-ForensicConfig.ps1'

Set-Content -Path `$tempScript -Value `$text -Encoding UTF8

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$tempScript -SecretsRoot 'C:\forensic_secrets'
    if (`$LASTEXITCODE -ne 0) {
        throw ('Remote Test-ForensicConfig.ps1 failed with exit code {0}' -f `$LASTEXITCODE)
    }
}
finally {
    Remove-Item `$tempScript -Force -ErrorAction SilentlyContinue
}
"@

    Invoke-RemotePS -Host $targetHost -Script $validatorScript | Out-Null

    Write-Host "[OK] Secrets validated on $targetHost."
}

Write-Host "[COMPLETE] Secrets prepared and synced to all hosts." -ForegroundColor Green
