param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,   # e.g. C:\development\forensic_suite_v2

    [Parameter(Mandatory = $true)]
    [string]$PayloadPath   # e.g. C:\development\forensic_tracer_installer_project_root\installer_payload
)

Write-Host "=== REFRESHING INSTALLER PAYLOAD ===" -ForegroundColor Cyan
Write-Host "Source:      $SourcePath"
Write-Host "Destination: $PayloadPath"
Write-Host ""

# -----------------------------
# 1. Validate paths
# -----------------------------
if (-not (Test-Path $SourcePath)) {
    Write-Error "Source path does not exist: $SourcePath"
    exit 1
}

if (-not (Test-Path $PayloadPath)) {
    Write-Host "Payload folder does not exist. Creating it..."
    New-Item -ItemType Directory -Path $PayloadPath | Out-Null
}

# -----------------------------
# 2. Delete existing payload contents
# -----------------------------
Write-Host "Deleting existing payload contents..." -ForegroundColor Yellow

Get-ChildItem -Path $PayloadPath -Force | ForEach-Object {
    try {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to delete: $($_.FullName) — $_"
    }
}

Write-Host "Payload cleared." -ForegroundColor Green

# -----------------------------
# 3. Copy new payload contents
# -----------------------------
Write-Host "Copying new payload from source..." -ForegroundColor Yellow

try {
    Copy-Item -Path (Join-Path $SourcePath "*") `
              -Destination $PayloadPath `
              -Recurse -Force -ErrorAction Stop
}
catch {
    Write-Error "Copy failed: $_"
    exit 1
}

Write-Host "Payload refreshed successfully." -ForegroundColor Green
Write-Host "=== DONE ===" -ForegroundColor Cyan
