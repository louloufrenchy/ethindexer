<#
.SYNOPSIS
    Performs a clean rollback for a single ingestion host.

.DESCRIPTION
    Rolls back the forensic suite slot (blue/green) and restarts services.

.PARAMETER TargetHost
    Host to roll back.

.EXAMPLE
    .\Rollback-ChainHost.ps1 -TargetHost 192.168.0.172
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetHost
)

Write-Host "=== Rollback for $TargetHost ===" -ForegroundColor Cyan

# Use orchestrator rollback module
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Rollback = Join-Path $ScriptRoot "..\orchestrator\Rollback.ps1"

ssh forensicuser@$TargetHost "powershell -Command `"$Rollback`""

ssh forensicuser@$TargetHost "powershell -Command Restart-Service forensic_orchestrator"

Write-Host "[OK] Rollback complete for $TargetHost" -ForegroundColor Green
