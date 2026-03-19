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

$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot  = Split-Path -Parent $ScriptRoot
$ResolvedRoot = Split-Path -Parent $PackageRoot

Set-Location $ResolvedRoot

$PythonCandidates = @(
    "C:\Program Files\Python314\python.exe",
    "C:\Program Files\Python313\python.exe",
    "C:\Program Files\Python312\python.exe",
    "C:\Program Files\Python311\python.exe",
    "python.exe"
)

$PythonExe = $null
foreach ($candidate in $PythonCandidates) {
    if ($candidate -eq "python.exe") {
        $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($cmd) {
            $PythonExe = $cmd.Source
            break
        }
    }
    elseif (Test-Path $candidate) {
        $PythonExe = $candidate
        break
    }
}

if (-not $PythonExe) {
    throw "Python executable not found."
}

$OrchestratorScript = Join-Path $ResolvedRoot "forensic_suite_v2\core\orchestrator.py"

if (-not (Test-Path $OrchestratorScript)) {
    throw "Orchestrator script not found at $OrchestratorScript"
}

$env:PYTHONPATH = $ResolvedRoot
$env:PYTHONUNBUFFERED = "1"

& $PythonExe $OrchestratorScript
exit $LASTEXITCODE