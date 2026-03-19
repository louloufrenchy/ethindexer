<#
.SYNOPSIS
    Unified operations tool for Forensic Suite V2 (blue/green architecture).

.DESCRIPTION
    Supports:
      - Installer Preflight
      - Slot Integrity Checksum
      - Slot Checksum Diff (blue vs green)
      - Cluster Health Dashboard
      - Minimal Uninstall
      - Full Uninstall
      - Remote Uninstall (JSON)
      - Cluster Uninstall (fan-out)
      - Rollback Uninstall (remove new slot + restore symlink)
      - Preflight Uninstall Check
      - Cluster env.json Diff
#>

param(
    # Install / Preflight
    [switch]$PreflightInstall,

    # Slot Integrity
    [switch]$Checksum,
    [switch]$ChecksumDiff,

    # Cluster Health
    [switch]$Dashboard,

    # Uninstall Modes
    [switch]$MinimalUninstall,
    [switch]$FullUninstall,
    [switch]$RemoteUninstall,
    [switch]$ClusterUninstall,
    [switch]$RollbackUninstall,
    [switch]$PreflightUninstall,
    [switch]$DiffEnv,

    # Shared
    [string]$SlotRoot = "",
    [string]$HostList = "F:\tools\forensic_hosts.txt",
    [switch]$JsonOutput,

    # Custom verbose switch (compact, color-coded logs)
    [switch]$Verbose
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

# =====================================================================
# VERBOSE LOGGING
# =====================================================================
function Write-OpLog {
    param(
        [string]$Message,
        [string]$Color = "Gray"
    )

    if ($Verbose) {
        Write-Host $Message -ForegroundColor $Color
    }
}
# =====================================================================
# UTILITY FUNCTIONS
# =====================================================================

function Stop-And-Delete-Service($svc, $result) {

    Write-OpLog "[svc] ${svc}: processing..." "Cyan"

    $existing = Get-Service -Name $svc -ErrorAction SilentlyContinue

    if (-not $existing) {
        Write-OpLog "[svc] ${svc}: already removed." "DarkGray"
        $result.stopped += $svc
        $result.deleted += $svc
        return
    }

    if ($existing.Status -eq 'Running') {
        Write-OpLog "[svc] ${svc}: stopping..." "Yellow"
        try {
            Stop-Service $svc -Force -ErrorAction Stop
            Write-OpLog "[svc] ${svc}: stopped." "Green"
            $result.stopped += $svc
        } catch {
            Write-OpLog "[svc] ${svc}: could not stop (non-fatal)." "DarkYellow"
            $result.errors += "Could not stop $svc (non-fatal): $_"
        }
    } else {
        Write-OpLog "[svc] ${svc}: not running." "DarkGray"
        $result.stopped += $svc
    }

    Write-OpLog "[svc] ${svc}: deleting..." "Yellow"
    try {
        sc.exe delete $svc | Out-Null
        Write-OpLog "[svc] ${svc}: deleted." "Green"
        $result.deleted += $svc
    } catch {
        Write-OpLog "[svc] ${svc}: could not delete (non-fatal)." "DarkYellow"
        $result.errors += "Could not delete $svc (non-fatal): $_"
    }
}

function Clear-Service-EnvVars($svc, $result) {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"

    if (!(Test-Path $regPath)) {
        Write-OpLog "[env] ${svc}: registry already gone." "DarkGray"
        $result.env_cleared += $svc
        return
    }

    Write-OpLog "[env] ${svc}: clearing Environment block..." "Yellow"
    try {
        Remove-ItemProperty -Path $regPath -Name "Environment" -ErrorAction SilentlyContinue
        Write-OpLog "[env] ${svc}: Environment cleared." "Green"
        $result.env_cleared += $svc
    } catch {
        Write-OpLog "[env] ${svc}: could not clear env (non-fatal)." "DarkYellow"
        $result.errors += "Could not clear env vars for $svc (non-fatal): $_"
    }
}

function Remove-Symlink($result) {
    if (Test-Path $symlink) {
        Write-OpLog "[symlink] removing $symlink..." "Yellow"
        try {
            Remove-Item $symlink -Force
            Write-OpLog "[symlink] removed." "Green"
            $result.symlink_removed = $true
        } catch {
            Write-OpLog "[symlink] failed to remove." "DarkYellow"
            $result.errors += "Failed to remove symlink"
        }
    } else {
        Write-OpLog "[symlink] ${symlink}: already missing." "DarkGray"
    }
}

function Remove-Slot($slot, $result) {
    if (Test-Path $slot) {
        Write-OpLog "[slot] removing $slot..." "Yellow"
        try {
            Remove-Item $slot -Recurse -Force
            Write-OpLog "[slot] removed: $slot" "Green"
            $result.slots_removed += $slot
        } catch {
            Write-OpLog "[slot] failed to remove $slot." "DarkYellow"
            $result.errors += "Failed to remove slot: $slot"
        }
    } else {
        Write-OpLog "[slot] ${slot}: already missing." "DarkGray"
    }
}

function Compute-Checksum($root) {
    Write-OpLog "[checksum] scanning $root..." "Cyan"
    $files = Get-ChildItem -Path $root -Recurse -File
    $hashes = foreach ($f in $files) {
        $h = Get-FileHash $f.FullName -Algorithm SHA256
        [PSCustomObject]@{
            Path = $f.FullName.Substring($root.Length).TrimStart('\')
            Hash = $h.Hash
        }
    }
    Write-OpLog "[checksum] completed for $root." "Green"
    return $hashes | Sort-Object Path
}
# =====================================================================
# MODE: INSTALLER PREFLIGHT
# =====================================================================
if ($PreflightInstall) {
    Write-OpLog "[preflight] starting installer preflight..." "Cyan"

    $checks = [ordered]@{
        host            = $env:COMPUTERNAME
        python_ok       = $false
        admin_ok        = $false
        secrets_dir_ok  = $false
        env_json_ok     = $false
        services_absent = $true
        errors          = @()
    }

    # Admin
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $checks.admin_ok = $true
        Write-OpLog "[preflight] admin: OK" "Green"
    } else {
        $checks.errors += "Not running as Administrator."
        Write-OpLog "[preflight] admin: NOT ELEVATED" "DarkYellow"
    }

    # Python
    try {
        python --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $checks.python_ok = $true
            Write-OpLog "[preflight] python: OK" "Green"
        } else {
            $checks.errors += "python not available."
            Write-OpLog "[preflight] python: NOT FOUND" "DarkYellow"
        }
    } catch {
        $checks.errors += "python not available."
        Write-OpLog "[preflight] python: NOT FOUND" "DarkYellow"
    }

    # Secrets directory
    if (Test-Path $secretRoot) {
        $checks.secrets_dir_ok = $true
        Write-OpLog "[preflight] secrets dir: OK ($secretRoot)" "Green"
    } else {
        Write-OpLog "[preflight] secrets dir: MISSING ($secretRoot)" "DarkYellow"
    }

    # env.json
    if (Test-Path $secretFile) {
        try {
            $null = Get-Content $secretFile -Raw | ConvertFrom-Json
            $checks.env_json_ok = $true
            Write-OpLog "[preflight] env.json: OK" "Green"
        } catch {
            $checks.errors += "env.json invalid JSON."
            Write-OpLog "[preflight] env.json: INVALID JSON" "DarkYellow"
        }
    } else {
        Write-OpLog "[preflight] env.json: MISSING" "DarkYellow"
    }

    # Services must not exist
    foreach ($svc in $services) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            $checks.services_absent = $false
            $checks.errors += "Service already present: $svc"
            Write-OpLog "[preflight] service present: ${svc}" "DarkYellow"
        } else {
            Write-OpLog "[preflight] service absent: ${svc}" "DarkGray"
        }
    }

    Write-OpLog "[preflight] complete." "Cyan"
    if ($JsonOutput) { $checks | ConvertTo-Json -Depth 5 } else { $checks }
    exit
}

# =====================================================================
# MODE: SLOT CHECKSUM
# =====================================================================
if ($Checksum) {
    if (-not $SlotRoot) { throw "Specify -SlotRoot" }
    if (!(Test-Path $SlotRoot)) { throw "Slot not found: $SlotRoot" }

    $hashes = Compute-Checksum $SlotRoot
    if ($JsonOutput) { $hashes | ConvertTo-Json -Depth 5 } else { $hashes }
    exit
}

# =====================================================================
# MODE: SLOT CHECKSUM DIFF (BLUE vs GREEN)
# =====================================================================
if ($ChecksumDiff) {
    Write-OpLog "[diff] checksum diff BLUE vs GREEN..." "Cyan"

    $result = [ordered]@{
        blue_exists  = Test-Path $blue
        green_exists = Test-Path $green
        diffs        = @()
        errors       = @()
    }

    if (-not $result.blue_exists -or -not $result.green_exists) {
        if (-not $result.blue_exists) {
            $result.errors += "Blue slot missing: $blue"
            Write-OpLog "[diff] blue slot missing: $blue" "DarkYellow"
        }
        if (-not $result.green_exists) {
            $result.errors += "Green slot missing: $green"
            Write-OpLog "[diff] green slot missing: $green" "DarkYellow"
        }

        if ($JsonOutput) { $result | ConvertTo-Json -Depth 10 } else { $result }
        exit
    }

    $blueMap  = Compute-Checksum $blue
    $greenMap = Compute-Checksum $green

    $blueDict  = @{}; $blueMap  | ForEach-Object { $blueDict[$_.Path]  = $_.Hash }
    $greenDict = @{}; $greenMap | ForEach-Object { $greenDict[$_.Path] = $_.Hash }

    $allKeys = ($blueDict.Keys + $greenDict.Keys) | Sort-Object -Unique

    foreach ($k in $allKeys) {
        $b = $blueDict[$k]
        $g = $greenDict[$k]

        if ($null -eq $b) {
            $result.diffs += "Only in GREEN: $k"
            continue
        }
        if ($null -eq $g) {
            $result.diffs += "Only in BLUE:  $k"
            continue
        }
        if ($b -ne $g) {
            $result.diffs += "HASH MISMATCH: $k"
        }
    }

    if ($result.diffs.Count -eq 0) {
        Write-OpLog "[diff] no differences." "Green"
    } else {
        Write-OpLog "[diff] differences found: $($result.diffs.Count)" "DarkYellow"
    }

    if ($JsonOutput) { $result | ConvertTo-Json -Depth 10 } else { $result }
    exit
}

# =====================================================================
# MODE: CLUSTER HEALTH DASHBOARD
# =====================================================================
if ($Dashboard) {
	if (-not $script:ForensicCred) {
		Write-OpLog "[dash] prompting for credentials..." "Cyan"
		#$script:ForensicCred = Get-Credential -Message "Enter forensicuser credentials"
	}
	
    if (!(Test-Path $HostList)) { throw "Host list not found: $HostList" }

    Write-OpLog "[dash] loading hosts from $HostList..." "Cyan"
    $hosts   = Get-Content $HostList | Where-Object { $_ -and $_.Trim() -ne "" }
    $results = @()

    foreach ($TargetHost in $hosts) {
        Write-OpLog "[dash] probing ${TargetHost}..." "Cyan"
        try {
            $res = Invoke-Command -ComputerName $TargetHost -ScriptBlock {
                $symlink  = "C:\forensic_suite_v2"
                $services = @("btc_indexer", "eth_indexer", "tron_indexer")

                $svcStates = @{}
                foreach ($s in $services) {
                    $svc = Get-Service $s -ErrorAction SilentlyContinue
                    if ($null -eq $svc) {
                        $svcStates[$s] = "Missing"
                    } else {
                        $svcStates[$s] = $svc.Status.ToString()
                    }
                }

                $slotTarget = if (Test-Path $symlink) { (Get-Item $symlink).Target } else { "Missing" }

                [ordered]@{
                    host     = $env:COMPUTERNAME
                    symlink  = $slotTarget
                    services = $svcStates
                }
            }

            Write-OpLog "[dash] ${TargetHost}: OK" "Green"
            $results += $res
        } catch {
            Write-OpLog "[dash] ${TargetHost}: probe failed." "DarkYellow"
            $results += [ordered]@{
                host  = $TargetHost
                error = "Probe failed: $_"
            }
        }
    }

    if ($JsonOutput) { $results | ConvertTo-Json -Depth 10 } else { $results }
    exit
}

# =====================================================================
# MODE: PREFLIGHT UNINSTALL
# =====================================================================
if ($PreflightUninstall) {
    Write-OpLog "[pre-uninstall] scanning local state..." "Cyan"
    $issues = @()

    foreach ($svc in $services) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            $issues += "Service present: $svc"
            Write-OpLog "[pre-uninstall] service present: $svc" "DarkYellow"
        }
    }

    if (Test-Path $symlink) {
        $issues += "Symlink exists: $symlink → $((Get-Item $symlink).Target)"
        Write-OpLog "[pre-uninstall] symlink exists: $symlink" "DarkYellow"
    } else {
        $issues += "Symlink missing"
        Write-OpLog "[pre-uninstall] symlink missing: $symlink" "DarkGray"
    }

    if (Test-Path $secretFile) {
        $issues += "env.json present"
        Write-OpLog "[pre-uninstall] env.json present." "Green"
    } else {
        $issues += "env.json missing"
        Write-OpLog "[pre-uninstall] env.json missing." "DarkYellow"
    }

    if ($JsonOutput) { $issues | ConvertTo-Json -Depth 5 } else { $issues }
    exit
}

# =====================================================================
# MODE: MINIMAL UNINSTALL
# =====================================================================
if ($MinimalUninstall) {
    Write-Host "=== MINIMAL UNINSTALL ===" -ForegroundColor Cyan

    $result = [ordered]@{
        stopped         = @()
        deleted         = @()
        env_cleared     = @()
        symlink_removed = $false
        errors          = @()
    }

    foreach ($svc in $services) {
        Stop-And-Delete-Service $svc $result
        Clear-Service-EnvVars   $svc $result
    }

    Remove-Symlink $result

    if ($JsonOutput) {
        $result | ConvertTo-Json -Depth 10
    } else {
        $result
    }

    exit
}

# =====================================================================
# MODE: FULL UNINSTALL
# =====================================================================
if ($FullUninstall) {
    Write-Host "=== FULL UNINSTALL ===" -ForegroundColor Cyan

    $result = [ordered]@{
        stopped         = @()
        deleted         = @()
        env_cleared     = @()
        symlink_removed = $false
        slots_removed   = @()
        secrets_removed = $false
        errors          = @()
    }

    foreach ($svc in $services) {
        Stop-And-Delete-Service $svc $result
        Clear-Service-EnvVars   $svc $result
    }

    Remove-Symlink $result
    Remove-Slot    $blue  $result
    Remove-Slot    $green $result

    if (Test-Path $secretRoot) {
        Write-OpLog "[secrets] removing $secretRoot..." "Yellow"
        try {
            Remove-Item $secretRoot -Recurse -Force
            Write-OpLog "[secrets] removed." "Green"
            $result.secrets_removed = $true
        } catch {
            Write-OpLog "[secrets] failed to remove." "DarkYellow"
            $result.errors += "Failed to remove secrets directory"
        }
    } else {
        Write-OpLog "[secrets] ${secretRoot}: already missing." "DarkGray"
    }

    if ($JsonOutput) { $result | ConvertTo-Json -Depth 10 } else { $result }
    exit
}

# =====================================================================
# MODE: ROLLBACK UNINSTALL
# =====================================================================
if ($RollbackUninstall) {
    Write-Host "=== ROLLBACK UNINSTALL ===" -ForegroundColor Cyan

    $result = [ordered]@{
        removed_slot     = $null
        symlink_restored = $false
        previous_target  = $null
        errors           = @()
    }

    if (!(Test-Path $symlink)) {
        Write-OpLog "[rollback] symlink missing; cannot rollback." "DarkYellow"
        $result.errors += "Symlink missing; cannot rollback."
        if ($JsonOutput) { $result | ConvertTo-Json -Depth 10 } else { $result }
        exit
    }

    $currentTarget          = (Get-Item $symlink).Target
    $result.previous_target = $currentTarget
    Write-OpLog "[rollback] current target: $currentTarget" "Cyan"

    $newSlot = $null
    $oldSlot = $null

    if ($currentTarget -like "*green") {
        $newSlot = $green
        $oldSlot = $blue
    } else {
        $newSlot = $blue
        $oldSlot = $green
    }

    Write-OpLog "[rollback] new slot: $newSlot; previous slot: $oldSlot" "Cyan"

    if (Test-Path $newSlot) {
        Write-OpLog "[rollback] removing new slot $newSlot..." "Yellow"
        try {
            Remove-Item $newSlot -Recurse -Force
            Write-OpLog "[rollback] removed new slot $newSlot." "Green"
            $result.removed_slot = $newSlot
        } catch {
            Write-OpLog "[rollback] failed to remove new slot $newSlot." "DarkYellow"
            $result.errors += "Failed to remove new slot: $newSlot (non-fatal): $_"
        }
    } else {
        Write-OpLog "[rollback] new slot not found: $newSlot" "DarkGray"
        $result.errors += "New slot not found: $newSlot (non-fatal)."
    }

    if (Test-Path $oldSlot) {
        Write-OpLog "[rollback] restoring symlink to $oldSlot..." "Yellow"
        try {
            Remove-Item $symlink -Force -ErrorAction SilentlyContinue
            New-Item -ItemType SymbolicLink -Path $symlink -Target $oldSlot | Out-Null
            Write-OpLog "[rollback] symlink restored to $oldSlot." "Green"
            $result.symlink_restored = $true
        } catch {
            Write-OpLog "[rollback] failed to restore symlink to $oldSlot." "DarkYellow"
            $result.errors += "Failed to restore symlink to $oldSlot (non-fatal): $_"
        }
    } else {
        Write-OpLog "[rollback] previous slot not found: $oldSlot" "DarkYellow"
        $result.errors += "Previous slot not found: $oldSlot (cannot restore symlink)."
    }

    if ($JsonOutput) { $result | ConvertTo-Json -Depth 10 } else { $result }
    exit
}

# =====================================================================
# MODE: REMOTE UNINSTALL
# =====================================================================
if ($RemoteUninstall) {
    Write-OpLog "[remote] uninstall on host $($env:COMPUTERNAME)..." "Cyan"

    $result = [ordered]@{
        host            = $env:COMPUTERNAME
        stopped         = @()
        deleted         = @()
        env_cleared     = @()
        symlink_removed = $false
        errors          = @()
    }

    foreach ($svc in $services) {
        Stop-And-Delete-Service $svc $result
        Clear-Service-EnvVars   $svc $result
    }

    Remove-Symlink $result

    if ($JsonOutput) { $result | ConvertTo-Json -Depth 10 } else { $result }
    exit
}

# =====================================================================
# MODE: CLUSTER UNINSTALL
# =====================================================================
if ($ClusterUninstall) {
    if (!(Test-Path $HostList)) { throw "Host list not found: $HostList" }

    Write-OpLog "[cluster-uninstall] loading hosts from $HostList..." "Cyan"
    $hosts   = Get-Content $HostList | Where-Object { $_ -and $_.Trim() -ne "" }
    $results = @()

    foreach ($TargetHost in $hosts) {
        Write-OpLog "[cluster-uninstall] ${TargetHost}: starting..." "Cyan"
        try {
            $remoteJson = Invoke-Command -ComputerName $TargetHost -ScriptBlock {
                F:\tools\ForensicSuiteV2-Operations.ps1 -RemoteUninstall -JsonOutput
            }

            try {
                $parsed = $remoteJson | ConvertFrom-Json
                Write-OpLog "[cluster-uninstall] ${host}: completed." "Green"
                $results += $parsed
            } catch {
                Write-OpLog "[cluster-uninstall] ${TargetHost}: invalid JSON from remote." "DarkYellow"
                $results += [ordered]@{
                    host  = $TargetHost
                    error = "Remote uninstall returned invalid JSON."
                }
            }
        } catch {
            Write-OpLog "[cluster-uninstall] ${TargetHost}: remote execution failed." "DarkYellow"
            $results += [ordered]@{
                host  = $host
                error = "Remote execution failed: $_"
            }
        }
    }

    if ($JsonOutput) { $results | ConvertTo-Json -Depth 10 } else { $results }
    exit
}

# =====================================================================
# MODE: CLUSTER ENV.JSON DIFF
# =====================================================================
if ($DiffEnv) {
    if (!(Test-Path $HostList)) { throw "Host list not found: $HostList" }

    Write-OpLog "[env-diff] loading hosts from $HostList..." "Cyan"
    $hosts = Get-Content $HostList | Where-Object { $_ -and $_.Trim() -ne "" }
    $envs  = @{}

    foreach ($TargetHost in $hosts) {
        Write-OpLog "[env-diff] fetching env.json from ${TargetHost}..." "Cyan"
        try {
            $content     = Invoke-Command -ComputerName $TargetHost -ScriptBlock {
                Get-Content "F:\forensic_secrets\env.json" -Raw
            }
            $envs[$TargetHost] = $content
            Write-OpLog "[env-diff] ${TargetHost}: OK" "Green"
        } catch {
            $envs[$TargetHost] = "ERROR"
            Write-OpLog "[env-diff] ${TargetHost}: ERROR" "DarkYellow"
        }
    }

    $baseline = $envs[$hosts[0]]
    $diffs    = @()

    foreach ($TargetHost in $hosts) {
		        if ($envs[$TargetHost] -ne $baseline) {
            $diffs += "DIFF: $TargetHost"
        }
    }

    if ($diffs.Count -eq 0) {
        Write-OpLog "[env-diff] all hosts match baseline." "Green"
    } else {
        Write-OpLog "[env-diff] differences on $($diffs.Count) host(s)." "DarkYellow"
    }

    if ($JsonOutput) { 
        $diffs | ConvertTo-Json -Depth 5 
    } else { 
        $diffs 
    }
    exit
}

# =====================================================================
# DEFAULT FALLBACK
# =====================================================================
Write-Host "No mode selected. Use -PreflightInstall, -Checksum, -ChecksumDiff, -Dashboard, -MinimalUninstall, -FullUninstall, -RemoteUninstall, -ClusterUninstall, -RollbackUninstall, -PreflightUninstall, or -DiffEnv."
