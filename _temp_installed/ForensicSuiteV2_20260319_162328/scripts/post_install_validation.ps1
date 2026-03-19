param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerExe
)

$ErrorActionPreference = "Stop"

if (-not $Global:PrimaryRoot) {
    throw "Global:PrimaryRoot is not set."
}

$root = $Global:PrimaryRoot
$script = Join-Path $root "post_install_validation.ps1"

Write-Host "=== [post_install_validation] Validating installer ==="
Write-Host "Installer: $InstallerExe"

if (-not (Test-Path $script)) {
    throw "Root script not found: $script"
}

if (-not (Test-Path $InstallerExe)) {
    throw "Installer EXE not found: $InstallerExe"
}

Push-Location $root
try {
    & $script -InstallerExe $InstallerExe
    if ($LASTEXITCODE -ne 0) {
        throw "post_install_validation.ps1 failed with exit code $LASTEXITCODE"
    }

    Write-Host "=== [post_install_validation] Completed successfully ==="
}
finally {
    Pop-Location
}
