<#
.SYNOPSIS
    Full reinstall of Forensic Suite V2 on one or more hosts (blue/green, DB untouched).

.DESCRIPTION
    This script:
      - Runs the unified uninstall (Minimal or Full) on target host(s)
      - Recreates blue/green slots and symlink
      - Ensures F:\forensic_secrets\env.json exists
      - Copies suite bits from a canonical source root
      - Rebuilds Python venv
      - Installs Windows services
      - Starts indexers + dashboard

    Database on 192.168.0.28 / forensic is NOT touched.

.PARAMETER Host
    Single host to reinstall.

.PARAMETER HostList
    File containing list of hosts (one per line).

.PARAMETER LocalRoot
    Canonical suite root on the laptop (source of truth).

.PARAMETER Mode
    Uninstall mode to use: Minimal or Full (default: Full).

.EXAMPLE
    F:\tools\ForensicSuiteV2-Reinstall.ps1 -Host WIN-U0AR3HQSOJB

.EXAMPLE
    F:\tools\ForensicSuiteV2-Reinstall.ps1 -HostList F:\tools\forensic_hosts.txt
#>

[CmdletBinding()]
param(
    [string]$TargetHost,
    [string]$HostList,
    [string]$LocalRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root",
    [ValidateSet("Minimal","Full")]
    [string]$Mode = "Full"
)

# =====================================================================
# VALIDATION
# =====================================================================

if (-not $TargetHost -and -not $HostList) {
    throw "Specify -Host or -HostList."
}

if (-not (Test-Path $LocalRoot)) {
    throw "LocalRoot not found: $LocalRoot"
}

$UninstallScript = "F:\tools\ForensicSuiteV2-Uninstall.ps1"
if (-not (Test-Path $UninstallScript)) {
    throw "Uninstall script not found: $UninstallScript"
}

# Optional but recommended: ensure global credential map exists
if (-not $Global:Creds) {
    Write-Warning "Global credential map (`$Global:Creds) is not defined. Hosts not in the map will prompt for credentials."
}

# Local credential cache to avoid repeated prompts in one run
if (-not $script:CredCache) {
    $script:CredCache = @{}
}

# =====================================================================
# TARGET HOST RESOLUTION
# =====================================================================

$targets = @()

if ($TargetHost) {
    $targets = @($TargetHost)
} elseif ($HostList) {
    if (-not (Test-Path $HostList)) {
        throw "Host list not found: $HostList"
    }
    $targets = Get-Content $HostList | Where-Object { $_ -and $_.Trim() -ne "" }
}

# =====================================================================
# PER-HOST REINSTALL LOGIC (CREDENTIAL-AWARE)
# =====================================================================

function Invoke-ReinstallOnHost {
    param(
        [string]$TargetHost,
        [string]$LocalRoot,
        [string]$UninstallScript,
        [string]$Mode
    )

    Write-Host "`n=== REINSTALL: $TargetHost ===" -ForegroundColor Cyan

    # Resolve credential for this host (flexible + cached)
    $cred = $null

    if ($script:CredCache.ContainsKey($TargetHost)) {
        $cred = $script:CredCache[$TargetHost]
        Write-Host "[$TargetHost] Using credential from in-session cache" -ForegroundColor DarkCyan
    } elseif ($Global:Creds -and $Global:Creds.ContainsKey($TargetHost)) {
        $cred = $Global:Creds[$TargetHost]
        $script:CredCache[$TargetHost] = $cred
        Write-Host "[$TargetHost] Using credential from `$Global:Creds" -ForegroundColor DarkCyan
    } else {
        Write-Host "[$TargetHost] No entry in `$Global:Creds. Prompting for credential..." -ForegroundColor DarkYellow
        $defaultUser = "$TargetHost\forensicuser"
        $cred = Get-Credential -Message "Enter credentials for $TargetHost" -UserName $defaultUser
        $script:CredCache[$TargetHost] = $cred
    }

    # 1. Reachability check
    if (-not (Test-Connection -ComputerName $TargetHost -Count 1 -Quiet)) {
        Write-Warning "Host $TargetHost is not reachable. Skipping."
        return [ordered]@{
            host    = $TargetHost
            status  = "UNREACHABLE"
            details = @("Ping failed")
        }
    }

    $result = [ordered]@{
        host    = $TargetHost
        status  = "UNKNOWN"
        steps   = @()
        errors  = @()
    }

    # 2. Run uninstall (Minimal or Full) remotely with execution policy bypass
    try {
        Write-Host "[$TargetHost] Running uninstall ($Mode)..." -ForegroundColor Yellow
        $uninstallJson = Invoke-Command -ComputerName $TargetHost -Credential $cred -ScriptBlock {
            param($scriptPath, $mode)

            # Execution policy bypass for this process only
            try {
                Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
            } catch {
                # Ignore if we can't change it; best-effort
            }

            if (-not (Test-Path $scriptPath)) {
                throw "Uninstall script not found: $scriptPath"
            }

            switch ($mode) {
                "Minimal" { & $scriptPath -Minimal | Out-String }
                "Full"    { & $scriptPath -Full    | Out-String }
            }
        } -ArgumentList $UninstallScript, $Mode

        $result.steps += "Uninstall ($Mode) executed."
    } catch {
        $msg = "Uninstall failed on ${TargetHost}: $($_.Exception.Message)"
        Write-Warning $msg
        $result.errors += $msg
        $result.status = "FAILED"
        return $result
    }

    # 3. Recreate secrets directory and ensure env.json exists
    try {
        Write-Host "[$TargetHost] Ensuring F:\forensic_secrets exists..." -ForegroundColor Yellow
        Invoke-Command -ComputerName $TargetHost -Credential $cred -ScriptBlock {
            if (-not (Test-Path "F:\forensic_secrets")) {
                New-Item -ItemType Directory -Path "F:\forensic_secrets" | Out-Null
            }
        }
        $result.steps += "Secrets directory ensured."
    } catch {
        $msg = "Failed to ensure secrets directory on ${TargetHost}: $($_.Exception.Message)"
        Write-Warning $msg
        $result.errors += $msg
    }

    # 4. Copy env.json from laptop to host (if present locally) using PSDrive
    $LocalSecret = Join-Path $LocalRoot "config\env.json"
    if (-not (Test-Path $LocalSecret)) {
        # Fallback: canonical env.json in F:\forensic_secrets on laptop
        $LocalSecret = "F:\forensic_secrets\env.json"
    }

    if (Test-Path $LocalSecret) {
        try {
            Write-Host "[$TargetHost] Copying env.json via PSDrive..." -ForegroundColor Yellow

            $driveName = "FS$($TargetHost.Replace('.', '_'))"

            # Create temporary PSDrive for this host with credentials
            New-PSDrive -Name $driveName -PSProvider FileSystem -Root "\\$TargetHost\C$" -Credential $cred -ErrorAction Stop | Out-Null

            try {
                $destPath = "$driveName`:\forensic_secrets\env.json"
                Copy-Item $LocalSecret $destPath -Force
                $result.steps += "env.json copied."
            } finally {
                # Always remove PSDrive
                Remove-PSDrive -Name $driveName -ErrorAction SilentlyContinue
            }
        } catch {
            $msg = "Failed to copy env.json to ${TargetHost}: $($_.Exception.Message)"
            Write-Warning $msg
            $result.errors += $msg
        }
    } else {
        $msg = "Local env.json not found at $LocalRoot\config\env.json or F:\forensic_secrets\env.json."
        Write-Warning $msg
        $result.errors += $msg
    }

    # 5. Recreate blue/green slots + symlink and copy suite bits
    try {
        Write-Host "[$TargetHost] Recreating blue/green slots + symlink..." -ForegroundColor Yellow

        Invoke-Command -ComputerName $TargetHost -Credential $cred -ScriptBlock {
            $blue    = "C:\forensic_suite_v2_blue"
            $green   = "C:\forensic_suite_v2_green"
            $symlink = "C:\forensic_suite_v2"

            # Clean any remnants
            if (Test-Path $blue)    { Remove-Item $blue    -Recurse -Force }
            if (Test-Path $green)   { Remove-Item $green   -Recurse -Force }
            if (Test-Path $symlink) { Remove-Item $symlink -Force }

            New-Item -ItemType Directory -Path $blue  | Out-Null
            New-Item -ItemType Directory -Path $green | Out-Null

            # Symlink points to blue by default
            New-Item -ItemType SymbolicLink -Path $symlink -Target $blue | Out-Null
        }

        # Copy suite bits from LocalRoot to blue slot
        Write-Host "[$TargetHost] Copying suite from $LocalRoot to blue slot..." -ForegroundColor Yellow
        $destBlue = "\\$TargetHost\C$\forensic_suite_v2_blue"
        robocopy $LocalRoot $destBlue /MIR /XF env.json /R:2 /W:2 | Out-Null

        $result.steps += "Blue/green slots recreated and suite copied."
    } catch {
        $msg = "Failed to recreate slots or copy suite on ${TargetHost}: $($_.Exception.Message)"
        Write-Warning $msg
        $result.errors += $msg
    }

    # 6. Rebuild Python venv + install requirements
    try {
        Write-Host "[$TargetHost] Rebuilding Python venv..." -ForegroundColor Yellow
        Invoke-Command -ComputerName $TargetHost -Credential $cred -ScriptBlock {
            $root = "C:\forensic_suite_v2"
            $venv = Join-Path $root "venv"

            if (Test-Path $venv) {
                Remove-Item $venv -Recurse -Force
            }

            Push-Location $root
            python -m venv venv
            & "$venv\Scripts\pip.exe" install -r "requirements.txt"
            Pop-Location
        }
        $result.steps += "Python venv rebuilt and requirements installed."
    } catch {
        $msg = "Failed to rebuild venv on ${TargetHost}: $($_.Exception.Message)"
        Write-Warning $msg
        $result.errors += $msg
    }

    # 7. Install services
    try {
        Write-Host "[$TargetHost] Installing services..." -ForegroundColor Yellow
        Invoke-Command -ComputerName $TargetHost -Credential $cred -ScriptBlock {
            $root = "C:\forensic_suite_v2"
            $script = Join-Path $root "scripts\install_services.ps1"
            if (-not (Test-Path $script)) {
                throw "install_services.ps1 not found at $script"
            }
            & $script
        }
        $result.steps += "Services installed."
    } catch {
        $msg = "Failed to install services on ${TargetHost}: $($_.Exception.Message)"
        Write-Warning $msg
        $result.errors += $msg
    }

    # 8. Start services
    try {
        Write-Host "[$TargetHost] Starting services..." -ForegroundColor Yellow
        Invoke-Command -ComputerName $TargetHost -Credential $cred -ScriptBlock {
            $services = @("btc_indexer","eth_indexer","tron_indexer","dashboard_service")
            foreach ($svc in $services) {
                if (Get-Service $svc -ErrorAction SilentlyContinue) {
                    Start-Service $svc -ErrorAction SilentlyContinue
                }
            }
        }
        $result.steps += "Services started."
    } catch {
        $msg = "Failed to start services on ${TargetHost}: $($_.Exception.Message)"
        Write-Warning $msg
        $result.errors += $msg
    }

    if ($result.errors.Count -eq 0) {
        $result.status = "SUCCESS"
    } else {
        $result.status = "PARTIAL"
    }

    return $result
}

# =====================================================================
# MAIN FAN-OUT
# =====================================================================

$allResults = @()

foreach ($t in $targets) {
    $allResults += Invoke-ReinstallOnHost -TargetHost $t -LocalRoot $LocalRoot -UninstallScript $UninstallScript -Mode $Mode
}

$allResults | ConvertTo-Json -Depth 10
