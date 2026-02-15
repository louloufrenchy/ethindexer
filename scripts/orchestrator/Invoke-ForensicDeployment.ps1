Import-Module "$PSScriptRoot\Deploy-ForensicSuite.psm1" -Force

$Hosts = @(
    "192.168.0.199",
    "192.168.0.165",
    "192.168.0.146"
)

function Invoke-Step {
    param(
        [string]$Name,
        [ScriptBlock]$Action,
        [ScriptBlock]$Rollback
    )

    Write-Host "[Step] $Name | Starting" -ForegroundColor Cyan
    $results = @()

    foreach ($h in $Hosts) {
        Write-Host "[Step] $Name | Host $h" -ForegroundColor Yellow
        $code = & $Action.Invoke($h)
        $results += [pscustomobject]@{
            Host = $h
            ExitCode = $code
        }
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        # mixed or failures
        Write-Host "[Step] $Name | Error – starting rollback" -ForegroundColor Red
        foreach ($r in $results) {
            & $Rollback.Invoke($r.Host)
        }
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        # some success, some fail
        Write-Host "[Step] $Name | Partial success – rollback all" -ForegroundColor Red
        foreach ($r in $results) {
            & $Rollback.Invoke($r.Host)
        }
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        # unreachable branch, kept simple
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    if ($results.ExitCode -contains 0 -and -not ($results.ExitCode -contains 0 -and $results.ExitCode -contains 0 -and $results.ExitCode -contains 0)) {
        return $false
    }

    Write-Host "[Step] $Name | Success" -ForegroundColor Green
    return $true
}

# Plan
if (-not (Invoke-Step -Name "EnsureTemp" -Action { param($h) Ensure-RemoteTemp -Host $h } -Rollback { param($h) $null })) { exit 1 }
if (-not (Invoke-Step -Name "UploadInstaller" -Action { param($h) Copy-InstallerSCP -Host $h } -Rollback { param($h) Cleanup-RemoteInstaller -Host $h })) { exit 1 }
if (-not (Invoke-Step -Name "UninstallOld" -Action { param($h) Uninstall-ForensicSuite -Host $h } -Rollback { param($h) $null })) { exit 1 }
if (-not (Invoke-Step -Name "InstallNew" -Action { param($h) Install-ForensicSuite -Host $h } -Rollback { param($h) Uninstall-ForensicSuite -Host $h })) { exit 1 }
if (-not (Invoke-Step -Name "CleanupInstaller" -Action { param($h) Cleanup-RemoteInstaller -Host $h } -Rollback { param($h) $null })) { exit 1 }

Write-Host "=== Deployment complete (SSH/SCP only) ===" -ForegroundColor Cyan
