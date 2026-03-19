<#
.SYNOPSIS
    Unified uninstall tool for Forensic Suite V2 (blue/green architecture).

.DESCRIPTION
    Supports:
      -Minimal uninstall
      -Full uninstall
      -Remote uninstall (JSON output)
      -Cluster uninstall (fan-out)
      -Rollback uninstall (remove new slot + revert symlink)
      -Pre-flight uninstall check
      -Cluster diff report (env.json comparison)

.PARAMETER Minimal
    Removes services + service env vars + symlink only.

.PARAMETER Full
    Removes services, env vars, symlink, slot directories, secrets.

.PARAMETER Remote
    Runs uninstall on a single host and returns JSON summary.

.PARAMETER Cluster
    Runs uninstall across all hosts in a host list.

.PARAMETER Rollback
    Removes the newly installed slot and restores previous symlink.

.PARAMETER Preflight
    Detects stale services, mismatched env vars, missing symlink, etc.

.PARAMETER Diff
    Compares env.json across all hosts and reports differences.
#>

[CmdletBinding()]
param(
    [switch]$Minimal,
    [switch]$Full,
    [switch]$Remote,
    [switch]$Cluster,
    [switch]$Rollback,
    [switch]$Preflight,
    [switch]$Diff,
    [string]$HostList = "F:\tools\forensic_hosts.txt",
    [switch]$JsonOutput
)

# =====================================================================
# CONSTANTS
# =====================================================================
$services   = @("btc_indexer", "eth_indexer", "tron_indexer")
$symlink    = "C:\forensic_suite_v2"
$blue       = "C:\forensic_suite_v2_blue"
$green      = "C:\forensic_suite_v2_green"
$secretRoot = "F:\forensic_secrets"
$secretFile = Join-Path $secretRoot "env.json"

# Resolve script path for remote execution
$ScriptPath = $MyInvocation.MyCommand.Path

# =====================================================================
# UTILITY FUNCTIONS
# =====================================================================

function New-ResultObject {
    param(
        [string]$HostName = $env:COMPUTERNAME
    )
    return [ordered]@{
        host            = $HostName
        stopped         = @()
        deleted         = @()
        env_cleared     = @()
        symlink_removed = $false
        slots_removed   = @()
        secrets_removed = $false
        removed_slot    = $null
        symlink_restored= $false
        errors          = @()
    }
}

function Stop-And-Delete-Service {
    param(
        [string]$ServiceName,
        [hashtable]$Result
    )

    if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {
        try {
            Stop-Service $ServiceName -Force -ErrorAction Stop
            $Result.stopped += $ServiceName
        } catch {
            $Result.errors += "Failed to stop service '$ServiceName': $($_.Exception.Message)"
        }

        try {
            sc.exe delete $ServiceName | Out-Null
            $Result.deleted += $ServiceName
        } catch {
            $Result.errors += "Failed to delete service '$ServiceName': $($_.Exception.Message)"
        }
    }
}

function Clear-Service-EnvVars {
    param(
        [string]$ServiceName,
        [hashtable]$Result
    )

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    if (Test-Path $regPath) {
        try {
            Remove-ItemProperty -Path $regPath -Name "Environment" -ErrorAction SilentlyContinue
            $Result.env_cleared += $ServiceName
        } catch {
            $Result.errors += "Failed to clear env vars for '$ServiceName': $($_.Exception.Message)"
        }
    }
}

function Remove-Symlink {
    param(
        [hashtable]$Result
    )

    if (Test-Path $symlink) {
        try {
            $item = Get-Item $symlink -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                Remove-Item $symlink -Force
                $Result.symlink_removed = $true
            } else {
                $Result.errors += "Path '$symlink' exists but is not a symlink."
            }
        } catch {
            $Result.errors += "Failed to remove symlink '$symlink': $($_.Exception.Message)"
        }
    }
}

function Remove-Slot {
    param(
        [string]$SlotPath,
        [hashtable]$Result
    )

    if (Test-Path $SlotPath) {
        try {
            Remove-Item $SlotPath -Recurse -Force
            $Result.slots_removed += $SlotPath
        } catch {
            $Result.errors += "Failed to remove slot '$SlotPath': $($_.Exception.Message)"
        }
    }
}

# =====================================================================
# MODE: PREFLIGHT CHECK
# =====================================================================
if ($Preflight) {
    Write-Host "=== PREFLIGHT UNINSTALL CHECK ===" -ForegroundColor Cyan

    $issues = @()

    foreach ($svc in $services) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            $issues += "Service present: $svc"
        }
    }

    if (Test-Path $symlink) {
        try {
            $target = (Get-Item $symlink).Target
            $issues += "Symlink exists: $symlink → $target"
        } catch {
            $issues += "Symlink exists but target could not be resolved: $symlink"
        }
    } else {
        $issues += "Symlink missing: $symlink"
    }

    if (Test-Path $secretFile) {
        $issues += "env.json present at $secretFile"
    } else {
        $issues += "env.json missing at $secretFile"
    }

    if ($issues.Count -eq 0) {
        Write-Host "[PASS] No uninstall blockers detected." -ForegroundColor Green
    } else {
        Write-Host "[INFO] Preflight findings:" -ForegroundColor Yellow
        $issues | ForEach-Object { Write-Host " - $_" }
    }

    exit
}

# =====================================================================
# MODE: MINIMAL UNINSTALL
# =====================================================================
if ($Minimal) {
    Write-Host "=== MINIMAL UNINSTALL ===" -ForegroundColor Cyan

    $result = New-ResultObject

    foreach ($svc in $services) {
        Stop-And-Delete-Service -ServiceName $svc -Result $result
        Clear-Service-EnvVars -ServiceName $svc -Result $result
    }

    Remove-Symlink -Result $result

    Write-Host "=== MINIMAL UNINSTALL COMPLETE ===" -ForegroundColor Green
    $result | ConvertTo-Json -Depth 10
    exit
}

# =====================================================================
# MODE: FULL UNINSTALL
# =====================================================================
if ($Full) {
    Write-Host "=== FULL UNINSTALL ===" -ForegroundColor Cyan

    $result = New-ResultObject

    foreach ($svc in $services) {
        Stop-And-Delete-Service -ServiceName $svc -Result $result
        Clear-Service-EnvVars -ServiceName $svc -Result $result
    }

    Remove-Symlink -Result $result
    Remove-Slot -SlotPath $blue -Result $result
    Remove-Slot -SlotPath $green -Result $result

    if (Test-Path $secretRoot) {
        try {
            Remove-Item $secretRoot -Recurse -Force
            $result.secrets_removed = $true
        } catch {
            $result.errors += "Failed to remove secrets directory '$secretRoot': $($_.Exception.Message)"
        }
    }

    Write-Host "=== FULL UNINSTALL COMPLETE ===" -ForegroundColor Green
    $result | ConvertTo-Json -Depth 10
    exit
}

# =====================================================================
# MODE: ROLLBACK UNINSTALL
# =====================================================================
if ($Rollback) {
    Write-Host "=== ROLLBACK UNINSTALL ===" -ForegroundColor Cyan

    $result = New-ResultObject

    if (!(Test-Path $symlink)) {
        $result.errors += "Symlink missing; cannot rollback."
        $result | ConvertTo-Json -Depth 10
        exit
    }

    try {
        $item   = Get-Item $symlink -ErrorAction Stop
        $target = $item.Target
    } catch {
        $result.errors += "Failed to resolve symlink target for '$symlink': $($_.Exception.Message)"
        $result | ConvertTo-Json -Depth 10
        exit
    }

    if ($target -match "green$") {
        $result.removed_slot = $green
        Remove-Slot -SlotPath $green -Result $result
        try {
            if (Test-Path $symlink) { Remove-Item $symlink -Force }
            New-Item -ItemType SymbolicLink -Path $symlink -Target $blue | Out-Null
            $result.symlink_restored = $true
        } catch {
            $result.errors += "Failed to restore symlink to blue: $($_.Exception.Message)"
        }
    } elseif ($target -match "blue$") {
        $result.removed_slot = $blue
        Remove-Slot -SlotPath $blue -Result $result
        try {
            if (Test-Path $symlink) { Remove-Item $symlink -Force }
            New-Item -ItemType SymbolicLink -Path $symlink -Target $green | Out-Null
            $result.symlink_restored = $true
        } catch {
            $result.errors += "Failed to restore symlink to green: $($_.Exception.Message)"
        }
    } else {
        $result.errors += "Symlink target '$target' does not match expected blue/green pattern."
    }

    Write-Host "=== ROLLBACK COMPLETE ===" -ForegroundColor Green
    $result | ConvertTo-Json -Depth 10
    exit
}

# =====================================================================
# MODE: REMOTE UNINSTALL
# =====================================================================
if ($Remote) {
    $result = New-ResultObject

    foreach ($svc in $services) {
        Stop-And-Delete-Service -ServiceName $svc -Result $result
        Clear-Service-EnvVars -ServiceName $svc -Result $result
    }

    Remove-Symlink -Result $result

    if ($JsonOutput) {
        $result | ConvertTo-Json -Depth 10
    } else {
        $result
    }

    exit
}

# =====================================================================
# MODE: CLUSTER UNINSTALL
# =====================================================================
if ($Cluster) {
    if (!(Test-Path $HostList)) {
        throw "Host list not found: $HostList"
    }

    $hosts   = Get-Content $HostList | Where-Object { $_ -and $_.Trim() -ne "" }
    $results = @()

    foreach ($TargetHost in $hosts) {
        try {
            $remoteJson = Invoke-Command `
                -ComputerName $TargetHost `
                -Authentication CredSSP `
                -Credential (Get-Credential) `
                -ScriptBlock {
                    param($remoteScriptPath)
                    & $remoteScriptPath -Remote -JsonOutput
                } -ArgumentList $ScriptPath

            $parsed = $remoteJson | ConvertFrom-Json
            $results += $parsed
        } catch {
            $results += [ordered]@{
                host            = $TargetHost
                stopped         = @()
                deleted         = @()
                env_cleared     = @()
                symlink_removed = $false
                slots_removed   = @()
                secrets_removed = $false
                removed_slot    = $null
                symlink_restored= $false
                errors          = @("Remote execution failed: $($_.Exception.Message)")
            }
        }
    }

    $results | ConvertTo-Json -Depth 10
    exit
}

# =====================================================================
# MODE: CLUSTER DIFF REPORT
# =====================================================================
if ($Diff) {
    if (!(Test-Path $HostList)) {
        throw "Host list not found: $HostList"
    }

    $hosts = Get-Content $HostList | Where-Object { $_ -and $_.Trim() -ne "" }
    $envs  = @{}

    foreach ($TargetHost in $hosts) {
        try {
            $content = Invoke-Command -ComputerName $TargetHost -ScriptBlock {
                param($path)
                if (Test-Path $path) {
                    Get-Content $path -Raw
                } else {
                    "MISSING"
                }
            } -ArgumentList $secretFile

            $envs[$TargetHost] = $content
        } catch {
            $envs[$TargetHost] = "ERROR: $($_.Exception.Message)"
        }
    }

    Write-Host "=== CLUSTER ENV.JSON DIFF REPORT ===" -ForegroundColor Cyan

    $baselineHost = $hosts[0]
    $baseline     = $envs[$baselineHost]

    foreach ($TargetHost in $hosts) {
        if ($envs[$TargetHost] -eq $baseline) {
            Write-Host "[MATCH] $host matches baseline ($baselineHost)" -ForegroundColor Green
        } else {
            Write-Host "[DIFF]  $host differs from baseline ($baselineHost)" -ForegroundColor Red
        }
    }

    exit
}

Write-Host "No mode selected. Use -Minimal, -Full, -Remote, -Cluster, -Rollback, -Preflight, or -Diff."
