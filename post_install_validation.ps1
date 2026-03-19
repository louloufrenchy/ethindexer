[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerExe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Post-Install Validation (Installer vs Payload, Hardened) ===" -ForegroundColor Cyan

if (-not $Global:PrimaryRoot) {
    throw "Global:PrimaryRoot is not set."
}

$Root        = $Global:PrimaryRoot
$PayloadRoot = Join-Path $Root "installer_payload"

if (-not (Test-Path $InstallerExe)) {
    throw "Installer EXE not found: $InstallerExe"
}

if (-not (Test-Path $PayloadRoot)) {
    throw "Installer payload not found: $PayloadRoot"
}

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

function Remove-PathIfExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path $Path) {
        try {
            attrib -r -s -h $Path /S /D 2>$null | Out-Null
        }
        catch {
        }

        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
        }
        catch {
            cmd /c "rmdir /s /q "$Path"" 2>$null | Out-Null
        }
    }
}

function Get-RelativeFiles {
    param([Parameter(Mandatory = $true)][string]$BasePath)

    $baseResolved = (Resolve-Path $BasePath).Path.TrimEnd('\')

    Get-ChildItem $baseResolved -Recurse -File -Force | ForEach-Object {
        [PSCustomObject]@{
            RelativePath = $_.FullName.Substring($baseResolved.Length).TrimStart('\')
            FullPath     = $_.FullName
        }
    }
}

function Test-BenignInstalledExtra {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $rp = $RelativePath -replace '/', '\'

    if ($rp -match '(^|\\)_pycache_(\\|$)') { return $true }
    if ($rp -like 'venv\*') { return $true }
    if ($rp -like 'ForensicSuite\*') { return $true }
    if ($rp -ieq 'unins000.exe') { return $true }
    if ($rp -ieq 'unins000.dat') { return $true }

    return $false
}

function Compare-Trees {
    param(
        [Parameter(Mandatory = $true)][string]$PayloadRoot,
        [Parameter(Mandatory = $true)][string]$InstalledRoot
    )

    $payloadFiles   = @(Get-RelativeFiles -BasePath $PayloadRoot)
    $installedFiles = @(Get-RelativeFiles -BasePath $InstalledRoot)

    $payloadMap   = @{}
    $installedMap = @{}

    foreach ($f in $payloadFiles)   { $payloadMap[$f.RelativePath]   = $f.FullPath }
    foreach ($f in $installedFiles) { $installedMap[$f.RelativePath] = $f.FullPath }

    $missing = New-Object System.Collections.Generic.List[object]
    $extra   = New-Object System.Collections.Generic.List[object]
    $drift   = New-Object System.Collections.Generic.List[object]

    foreach ($rel in ($payloadMap.Keys | Sort-Object)) {
        if (-not $installedMap.ContainsKey($rel)) {
            $missing.Add([PSCustomObject]@{
                RelativePath = $rel
                PayloadPath  = $payloadMap[$rel]
            })
            continue
        }

        $hashPayload  = (Get-FileHash $payloadMap[$rel]  -Algorithm SHA256).Hash
        $hashInstalled = (Get-FileHash $installedMap[$rel] -Algorithm SHA256).Hash

        if ($hashPayload -ne $hashInstalled) {
            $drift.Add([PSCustomObject]@{
                RelativePath  = $rel
                PayloadPath   = $payloadMap[$rel]
                InstalledPath = $installedMap[$rel]
            })
        }
    }

    foreach ($rel in ($installedMap.Keys | Sort-Object)) {
        if (-not $payloadMap.ContainsKey($rel)) {
            if (-not (Test-BenignInstalledExtra -RelativePath $rel)) {
                $extra.Add([PSCustomObject]@{
                    RelativePath = $rel
                    FullPath     = $installedMap[$rel]
                })
            }
        }
    }

    return [PSCustomObject]@{
        Missing = $missing
        Extra   = $extra
        Drift   = $drift
    }
}

# ---------------------------------------------------------------------
# Temp install target
# ---------------------------------------------------------------------

$TempRoot     = Join-Path $Root "_temp_installed"
$InstallStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$InstallRoot  = Join-Path $TempRoot "ForensicSuiteV2_$InstallStamp"

Write-Host ""
Write-Host "[1/5] Preparing temporary install directory..." -ForegroundColor Cyan
Remove-PathIfExists -Path $InstallRoot
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

# ---------------------------------------------------------------------
# Run installer into temp target
# ---------------------------------------------------------------------

Write-Host "[2/5] Running silent installer into temp directory..." -ForegroundColor Cyan

$installerArgs = @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/NORESTART",
    "/SP-",
    "/DIR=$InstallRoot"
)

$proc = Start-Process -FilePath $InstallerExe -ArgumentList $installerArgs -Wait -PassThru

if ($proc.ExitCode -ne 0) {
    throw "Installer exited with code $($proc.ExitCode)"
}

if (-not (Test-Path $InstallRoot)) {
    throw "Installer completed but temp install root was not created: $InstallRoot"
}

$installedFileCount = (Get-ChildItem $InstallRoot -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count
if ($installedFileCount -lt 1) {
    throw "Temp install directory is empty after install: $InstallRoot"
}

Write-Host "[OK] Using install root: $InstallRoot" -ForegroundColor Green

# ---------------------------------------------------------------------
# Compare payload vs installed temp root
# ---------------------------------------------------------------------

Write-Host "[3/5] Building file comparison lists..." -ForegroundColor Cyan
$result = Compare-Trees -PayloadRoot $PayloadRoot -InstalledRoot $InstallRoot

Write-Host ""
Write-Host "=== Missing in Installed (should have been installed) ===" -ForegroundColor Yellow
if ($result.Missing.Count -eq 0) {
    Write-Host "None." -ForegroundColor Green
}
else {
    $result.Missing | Sort-Object RelativePath | Format-Table -AutoSize
}

Write-Host ""
Write-Host "=== Extra in Installed (not in payload, excluding benign residue) ===" -ForegroundColor Yellow
if ($result.Extra.Count -eq 0) {
    Write-Host "None." -ForegroundColor Green
}
else {
    $result.Extra | Sort-Object RelativePath | Format-Table -AutoSize
}

Write-Host ""
Write-Host "=== Drift (hash mismatch) ===" -ForegroundColor Yellow
if ($result.Drift.Count -eq 0) {
    Write-Host "None." -ForegroundColor Green
}
else {
    $result.Drift | Sort-Object RelativePath | Format-Table -AutoSize
}

# ---------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------

Write-Host ""
if ($result.Missing.Count -eq 0 -and $result.Extra.Count -eq 0 -and $result.Drift.Count -eq 0) {
    Write-Host "[SUCCESS] Installed content matches installer_payload." -ForegroundColor Green
    Write-Host "Temp install directory: $InstallRoot" -ForegroundColor Gray
    exit 0
}
else {
    Write-Host "[WARNING] Installed content does NOT match installer_payload." -ForegroundColor Yellow
    Write-Host "Temp install directory: $InstallRoot" -ForegroundColor Gray
    exit 1
}