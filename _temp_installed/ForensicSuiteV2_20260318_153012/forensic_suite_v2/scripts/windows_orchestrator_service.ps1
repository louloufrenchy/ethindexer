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
if (-not $Global:PythonExe) {
    throw "Global PythonExe not defined. Ensure your profile sets `$Global:PythonExe."
}

$PythonExe = $Global:PythonExe

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
