<#
.SYNOPSIS
    Deploys the Forensic Suite V2 installer to a remote host using SSH/SCP.
    Includes Blue/Green slot detection and post-install cleanup.

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