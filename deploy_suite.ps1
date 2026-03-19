<#
.SYNOPSIS
<<<<<<< HEAD
    Deploys the Forensic Suite V2 installer to a remote host using blue/green deployment.
=======
    Deploys the Forensic Suite V2 installer to a remote host using SSH/SCP.
    Includes Blue/Green slot detection and post-install cleanup.
>>>>>>> master

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
<<<<<<< HEAD
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
=======
    [Parameter(Mandatory = $true)][string]$TargetHost,
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [switch]$BlueGreen
)

Write-Host "=== FORENSIC SUITE V2 SSH-DEPLOYMENT STARTED ===" -ForegroundColor Cyan
$sshKey = "$env:USERPROFILE\.ssh\id_ed25519"
$remoteInstaller = "C:/forensic_suite_v2_installer.exe"

# 1. Copy installer via SCP
Write-Host ">>> Copying installer via SCP to ${TargetHost}..." -ForegroundColor Yellow
scp -i $sshKey $InstallerPath "forensicuser@${TargetHost}:${remoteInstaller}"
if ($LASTEXITCODE -ne 0) { throw "SCP failed to $TargetHost" }

# 2. Determine Slot via SSH
$deploymentSlot = "green"
if ($BlueGreen) {
    Write-Host ">>> Checking active slot..."
    $targetPath = ssh -i $sshKey "forensicuser@${TargetHost}" 'powershell -Command "if(Test-Path C:\forensic_suite_v2){(Get-Item C:\forensic_suite_v2).Target}else{write-host None}"'
    if ($targetPath -like "*green*") { $deploymentSlot = "blue" }
}
$installDir = "C:\forensic_suite_v2_$deploymentSlot"

# 3. Pre-Install Lockdown (Release Locks)
Write-Host ">>> Stopping services to release symlink locks..." -ForegroundColor Gray
ssh -i $sshKey "forensicuser@${TargetHost}" 'powershell -Command "Stop-Service btc_indexer, eth_indexer, tron_indexer -Force -ErrorAction SilentlyContinue"'

# 4. Remote Execution via SSH (Silently)
Write-Host ">>> Executing installer on $TargetHost (Target: $installDir)..." -ForegroundColor Yellow
$remoteCmd = "powershell -Command ""Start-Process ${remoteInstaller} -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /DIR=$installDir' -Wait"""
ssh -i $sshKey "forensicuser@${TargetHost}" $remoteCmd

# 5. Finalize Symlink (Hardened CMD Logic)
# Hardened Link Update: Remove if exists, then always create
$linkCmd = "cmd /c ""if exist C:\forensic_suite_v2 (rmdir C:\forensic_suite_v2)"" ; cmd /c ""mklink /d C:\forensic_suite_v2 $installDir"""
ssh -i $sshKey "forensicuser@${TargetHost}" $linkCmd

# 6. Start TRON Service (Asynchronous Start)
Write-Host ">>> Triggering TRON Service (Async)..."
# We trigger the start but do not wait for the SCM handshake to return to avoid hangs
ssh -i $sshKey "forensicuser@${TargetHost}" 'powershell -Command "Start-Job -ScriptBlock { Start-Service tron_indexer -ErrorAction SilentlyContinue }"'

# 7. Post-Installation Cleanup
Write-Host ">>> Purging remote installers and legacy temp files..." -ForegroundColor Gray
$cleanupCmd = "powershell -Command ""Remove-Item ${remoteInstaller}, C:\Temp\ForensicSuiteV2-Setup.exe -Force -ErrorAction SilentlyContinue"""
ssh -i $sshKey "forensicuser@${TargetHost}" $cleanupCmd

Write-Host "`n=== DEPLOYMENT TO $TargetHost COMPLETE ===" -ForegroundColor Green
>>>>>>> master
