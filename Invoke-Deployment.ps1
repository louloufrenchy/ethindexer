# Invoke-Deployment.ps1
Import-Module ".\installer_payload\ForensicSuite\scripts\orchestrator\Orchestrator.psm1" -Force

# Resolve paths locally where we know they work
$localInstaller = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\Output\ForensicSuiteV2-Setup.exe"
$sshKey = "$env:USERPROFILE\.ssh\id_ed25519"
$remotePath = "C:\Temp\ForensicSuiteV2-Setup.exe"

Write-Host "Starting Deployment to Windows Server 2025 Cluster..." -ForegroundColor Cyan

# STEP 1: Setup Temp (Using Orchestrator)
if (-not (Invoke-Step -Name "1. Setup Remote Temp" -ActionName "Ensure-RemoteTemp")) { exit }

# STEP 2: Parallel Upload (Using native PWSH 7 Parallelism for stability)
Write-Host "`n=== 2. Upload Installer (Native Parallel) ===" -ForegroundColor Cyan
$hosts = @("192.168.0.199", "192.168.0.165", "192.168.0.146")

$hosts | ForEach-Object -Parallel {
    $ip = $_
    Write-Host "[$ip] Starting Upload..." -ForegroundColor Gray
    # Use the variables passed from the outer scope using $using:
    scp -i $using:sshKey -o "StrictHostKeyChecking=no" -o "BatchMode=yes" $using:localInstaller "forensicuser@$($ip):$using:remotePath"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[$ip] Upload Complete!" -ForegroundColor Green
    } else {
        Write-Host "[$ip] Upload FAILED with Exit $LASTEXITCODE" -ForegroundColor Red
    }
} -ThrottleLimit 3

# STEP 3: Execute Installation (Using Orchestrator)
Invoke-Step -Name "3. Execute Installation" -ActionName "Install-ForensicSuite"

# STEP 4: Health Check
Invoke-Step -Name "4. Verify Health" -ActionName "HealthCheck"
