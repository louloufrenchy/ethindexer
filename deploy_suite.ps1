<#
.SYNOPSIS
    Deploys the Forensic Suite V2 installer to a remote host using blue/green deployment.

.PARAMETER TargetHost
    The hostname or IP of the remote machine.

.PARAMETER InstallerPath
    Full path to the ForensicSuiteV2-Setup.exe installer.

.PARAMETER Credential
    PSCredential object for authentication.

.PARAMETER BlueGreen
    Switch to enable blue/green deployment mode.

.EXAMPLE
    .\deploy_suite.ps1 -TargetHost "WIN-1V7900SUQ9A" -InstallerPath "C:\installer\ForensicSuiteV2-Setup.exe" -Credential $cred -BlueGreen
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetHost,

    [Parameter(Mandatory=$true)]
    [string]$InstallerPath,

    [Parameter(Mandatory=$true)]
    [pscredential]$Credential,

    [switch]$BlueGreen
)

Write-Host "=== FORENSIC SUITE V2 DEPLOYMENT STARTED ===" -ForegroundColor Cyan
Write-Host "Target Host: $TargetHost"
Write-Host "Installer: $InstallerPath"
Write-Host "Blue/Green Mode: $BlueGreen"
Write-Host ""

# -----------------------------
# 1. Validate installer exists
# -----------------------------
if (-not (Test-Path $InstallerPath)) {
    Write-Error "Installer not found at: $InstallerPath"
    exit 1
}

# -----------------------------
# 2. Copy installer to remote host
# -----------------------------
$remoteInstallerPath = "C:\forensic_suite_v2_installer.exe"

Write-Host "Copying installer to $TargetHost..."
Copy-Item -Path $InstallerPath -Destination "\\$TargetHost\C$\forensic_suite_v2_installer.exe" -Force -ErrorAction Stop

Write-Host "Installer copied successfully." -ForegroundColor Green

# -----------------------------
# 3. Determine blue/green target
# -----------------------------
$deploymentSlot = "green"

if ($BlueGreen) {
    Write-Host "Checking active deployment slot on remote host..."

    $activeSlot = Invoke-Command -ComputerName $TargetHost -Credential $Credential -ScriptBlock {
        if (Test-Path "C:\forensic_suite_v2") {
            $link = Get-Item "C:\forensic_suite_v2"
            return $link.Target
        }
        return $null
    }

    if ($activeSlot -like "*green*") {
        $deploymentSlot = "blue"
    } else {
        $deploymentSlot = "green"
    }

    Write-Host "Active slot: $activeSlot"
    Write-Host "Deploying to: $deploymentSlot" -ForegroundColor Yellow
}

$installDir = "C:\forensic_suite_v2_$deploymentSlot"

# -----------------------------
# 4. Run installer silently
# -----------------------------
Write-Host "Running installer on remote host..."

Invoke-Command -ComputerName $TargetHost -Credential $Credential -ScriptBlock {
    param($remoteInstallerPath, $installDir)

    Write-Host "Installing to $installDir..."

    Start-Process -FilePath $remoteInstallerPath `
        -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /DIR=$installDir" `
        -Wait -NoNewWindow

    Write-Host "Installer completed."
} -ArgumentList $remoteInstallerPath, $installDir

Write-Host "Installer executed successfully." -ForegroundColor Green

# -----------------------------
# 5. Update symlink
# -----------------------------
if ($BlueGreen) {
    Write-Host "Updating symlink C:\forensic_suite_v2 → $installDir"

    Invoke-Command -ComputerName $TargetHost -Credential $Credential -ScriptBlock {
        param($installDir)

        if (Test-Path "C:\forensic_suite_v2") {
            Remove-Item "C:\forensic_suite_v2" -Force
        }

        New-Item -ItemType SymbolicLink -Path "C:\forensic_suite_v2" -Target $installDir | Out-Null
    } -ArgumentList $installDir

    Write-Host "Symlink updated." -ForegroundColor Green
}

# -----------------------------
# 6. Start TRON indexer service
# -----------------------------
Write-Host "Starting TRON indexer service..."

Invoke-Command -ComputerName $TargetHost -Credential $Credential -ScriptBlock {
    if (Get-Service tron_indexer -ErrorAction SilentlyContinue) {
        Start-Service tron_indexer -ErrorAction SilentlyContinue
    }
}

Write-Host "TRON indexer service started (if installed)." -ForegroundColor Green

Write-Host ""
Write-Host "=== DEPLOYMENT COMPLETE ===" -ForegroundColor Cyan
