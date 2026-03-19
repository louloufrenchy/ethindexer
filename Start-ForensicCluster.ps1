# Start-ForensicCluster.ps1
Import-Module ".\scripts\orchestrator\Orchestrator.psm1" -Force

Write-Host "Initializing Forensic Cluster Services..." -ForegroundColor Cyan

$hosts = @(
    @{ ip = "192.168.0.199"; roles = @("forensic", "btc", "eth", "tron") },
    @{ ip = "192.168.0.165"; roles = @("forensic", "btc") },
    @{ ip = "192.168.0.146"; roles = @("forensic", "tron") }
)

foreach ($h in $hosts) {
    Write-Host "`n--- Configuring Node $($h.ip) ---" -ForegroundColor Yellow
    
    # 1. Start the Base Forensic Engine (GUI/API Backend)
    if ($h.roles -contains "forensic") {
        Write-Host "[$($h.ip)] Launching Forensic Engine..."
        $cmd = "Start-Process -FilePath 'C:\Program Files\ForensicSuiteV2\ForensicSuite\ForensicSuite.exe' -WindowStyle Hidden"
        Invoke-Ssh -TargetHost $h.ip -ScriptText $cmd
    }

    # 2. Start Chain-Specific Indexers via the Venv
    foreach ($role in $h.roles) {
        if ($role -eq "forensic") { continue }
        
        Write-Host "[$($h.ip)] Starting $role Indexer..."
        $indexerScript = "C:\Program Files\ForensicSuiteV2\scripts\$($role)_dashboard.ps1"
        $launch = "& 'C:\Program Files\ForensicSuiteV2\venv\Scripts\python.exe' '$indexerScript' > '$role_indexer.log' 2>&1"
        Invoke-Ssh -TargetHost $h.ip -ScriptText "Start-Process powershell -ArgumentList '-NoProfile -Command $launch' -WindowStyle Hidden"
    }
}

Write-Host "`nCluster Start Sequence Initiated." -ForegroundColor Green