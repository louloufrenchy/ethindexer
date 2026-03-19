<<<<<<< HEAD
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
=======
<#
.SYNOPSIS
    Windows service entrypoint for the Forensic Suite orchestrator.

.DESCRIPTION
    - Resolves runtime root dynamically from the deployed script path
    - Avoids hardcoded development paths
    - Safe for blue/green deployed roots such as C:\forensic_suite_v2
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve deployed root
$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot  = Split-Path -Parent $ScriptRoot
$ResolvedRoot = Split-Path -Parent $PackageRoot

Set-Location $ResolvedRoot

# ---------------------------------------------------------------------
#  Authoritative Python resolution (NO HARDCODED PATHS)
# ---------------------------------------------------------------------
$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot  = Split-Path -Parent $ScriptRoot
$ResolvedRoot = Split-Path -Parent $PackageRoot

$PythonExe = Join-Path $ResolvedRoot "python\python.exe"

if (-not (Test-Path $PythonExe)) {
    throw "Python interpreter not found at $PythonExe"
}

# ---------------------------------------------------------------------
#  Orchestrator entrypoint
# ---------------------------------------------------------------------
$OrchestratorScript = Join-Path $ResolvedRoot "forensic_suite_v2\core\orchestrator.py"

if (-not (Test-Path $OrchestratorScript)) {
    throw "Orchestrator script not found at $OrchestratorScript"
}

$env:PYTHONPATH = $ResolvedRoot
$env:PYTHONUNBUFFERED = "1"

& $PythonExe $OrchestratorScript
exit $LASTEXITCODE
>>>>>>> master
