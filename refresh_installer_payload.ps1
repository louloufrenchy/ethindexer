param(
    [string]$ProjectRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)

# ----------------------------------------------------------------------
# SHIM ONLY (DO NOT EDIT BUSINESS LOGIC HERE)
# Real implementation lives at: scripts\refresh_installer_payload.ps1
# This file exists for backwards-compatibility (Preflight, older tooling).
# ----------------------------------------------------------------------

$impl = Join-Path $ProjectRoot "scripts\refresh_installer_payload.ps1"

if (-not (Test-Path $impl)) {
    Write-Host "[ERROR] Missing payload refresh implementation: $impl" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Using implementation: $impl" -ForegroundColor DarkGray
& $impl -ProjectRoot $ProjectRoot
exit $LASTEXITCODE