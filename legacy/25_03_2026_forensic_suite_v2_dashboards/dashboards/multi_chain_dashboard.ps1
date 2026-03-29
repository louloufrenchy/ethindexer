$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Py = "C:\forensic_suite_v2\python\python.exe"
$Script = Join-Path $Root "forensic_dashboard_cli.py"

if (-not (Test-Path $Py)) {
    throw "Python runtime not found at $Py"
}

if (-not (Test-Path $Script)) {
    throw "Dashboard CLI not found at $Script"
}

& $Py $Script --refresh 2.0
