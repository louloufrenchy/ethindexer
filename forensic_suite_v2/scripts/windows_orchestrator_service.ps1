param(
    [string]$PythonPath = "python",
    [string]$WorkingDir = "C:\development\forensic_suite_v2"
)

Set-Location $WorkingDir

$logDir = Join-Path $WorkingDir "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$logFile = Join-Path $logDir "orchestrator_service.log"

"[$(Get-Date)] Starting orchestrator service..." | Out-File -FilePath $logFile -Append

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $PythonPath
$psi.Arguments = "tron_indexer\services\orchestrator_service.py"
$psi.WorkingDirectory = $WorkingDir
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$proc.Start() | Out-Null

while (-not $proc.HasExited) {
    $out = $proc.StandardOutput.ReadLine()
    if ($out) {
        "[$(Get-Date)] $out" | Out-File -FilePath $logFile -Append
    }
    Start-Sleep -Milliseconds 200
}

"[$(Get-Date)] Orchestrator service exited with code $($proc.ExitCode)" | Out-File -FilePath $logFile -Append
