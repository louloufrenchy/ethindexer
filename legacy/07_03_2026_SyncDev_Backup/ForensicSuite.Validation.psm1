# =====================================================================
# ForensicSuite.Validation.psm1 (V9.3.4)
# Unified Validation + Sync-Dev + Cleanup + Deploy + Status Module
# =====================================================================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# =====================================================================
# 0. HELP / BANNER
# =====================================================================

function Get-ForensicSuiteHelp {
    Write-Host ""
    Write-Host "=== Forensic Suite Workspace V9.3.4 ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Modules Imported:" -ForegroundColor Yellow
	(Get-Command -Module ForensicSuite.Validation -CommandType Function |
    Sort-Object Name |
    Select-Object -ExpandProperty Name) |
    ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "Quick Options:" -ForegroundColor Yellow
    Write-Host "  Get-ForensicSuiteHelp   (paged help overview)"
    Write-Host "  Invoke-BuildSuiteSafe   (clean + deterministic full build)"
    Write-Host "  Get-StatusReport        (runtime / cluster health report)"
    Write-Host ""
    Write-Host "Convenience aliases:" -ForegroundColor Yellow
    Write-Host "  cleanall"
    Write-Host "  payloadfix"
    Write-Host "  restore"
    Write-Host "  safe-build"
    Write-Host "  syncdev"
    Write-Host "  validate"
    Write-Host ""
}

function Invoke-RemotePS {
    param(
        [Parameter(Mandatory = $true)][string]$Host,
        [Parameter(Mandatory = $true)][string]$Script
    )

    $sshExe = "$env:WINDIR\System32\OpenSSH\ssh.exe"

    $wrappedScript = @"
`$ProgressPreference    = 'SilentlyContinue'
`$InformationPreference = 'SilentlyContinue'
`$WarningPreference     = 'SilentlyContinue'
`$ErrorActionPreference = 'Stop'

$Script
"@

    $bytes   = [System.Text.Encoding]::Unicode.GetBytes($wrappedScript)
    $encoded = [Convert]::ToBase64String($bytes)

    $result = & $sshExe `
        -i $Global:SSHKey `
        "forensicuser@$Host" `
        "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand $encoded" `
        2>$null

    if ($LASTEXITCODE -ne 0) {
        return "SSH_ERROR"
    }

    return (($result | Out-String).Trim())
}

# =====================================================================
# 1. CLEANUP & VALIDATION
# =====================================================================

function Clear-ForensicSuiteAll {
    param(
        [string]$RepoA = $Global:PrimaryRoot,
        [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
    )

    Write-Host "=== Clear-ForensicSuiteAll (V9.3.4) ===" -ForegroundColor Cyan
    Write-Host "Repo A: $RepoA" -ForegroundColor Gray
    Write-Host "Repo B: $RepoB" -ForegroundColor Gray

    $cleanup = Join-Path $RepoA "scripts\forensic_suite_RepoB_cleanup.ps1"
    if (!(Test-Path $cleanup)) {
        Write-Host "[ERROR] RepoB cleanup script missing: $cleanup" -ForegroundColor Red
        return 99
    }

    & $cleanup -RepoB $RepoB
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ABORT] Repo B cleanup failed with code $LASTEXITCODE." -ForegroundColor Red
        return $LASTEXITCODE
    }

    Write-Host "[OK] Repo B cleaned (empty, ready for Sync-Dev)." -ForegroundColor Green
    return 0
}

function Test-ForensicSuiteAll {
    param(
        [string]$RepoA = $Global:PrimaryRoot,
        [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
    )

    $validator = Join-Path $RepoA "scripts\forensic_suite_Combined_validator.ps1"

    if (!(Test-Path $validator)) {
        Write-Host "[ERROR] Combined validator missing: $validator" -ForegroundColor Red
        return 99
    }

    & $validator -RepoA $RepoA -RepoB $RepoB
    return $LASTEXITCODE
}

function Restore-Workspace {
    param(
        [string]$RepoA = $Global:PrimaryRoot,
        [string]$RepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
    )

    Write-Host "`n=== Restore-Workspace (V9.3.4 — Deterministic Recovery) ===" -ForegroundColor Cyan
    Write-Host "Repo A: $RepoA" -ForegroundColor Gray
    Write-Host "Repo B: $RepoB" -ForegroundColor Gray

    # 1. Clear Repo B
    $cleanup = Join-Path $RepoA "scripts\forensic_suite_RepoB_cleanup.ps1"
    if (!(Test-Path $cleanup)) {
        Write-Host "[ERROR] Cleanup script missing: $cleanup" -ForegroundColor Red
        return 99
    }

    Write-Host "`n>>> Clearing Repo B..." -ForegroundColor Yellow
    & $cleanup -RepoB $RepoB
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ABORT] Repo B cleanup failed with code $LASTEXITCODE." -ForegroundColor Red
        return $LASTEXITCODE
    }

    # 2. Preflight
    $preflight = Join-Path $RepoA "scripts\Invoke-Preflight.ps1"
    if (!(Test-Path $preflight)) {
        Write-Host "[ERROR] Preflight script missing: $preflight" -ForegroundColor Red
        return 98
    }

    Write-Host "`n>>> Running Preflight..." -ForegroundColor Yellow
    & $preflight -RepoA $RepoA -RepoB $RepoB
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ABORT] Repair blocked by Preflight failure (code $LASTEXITCODE)." -ForegroundColor Red
        return $LASTEXITCODE
    }

    # 3. Sync-Dev Apply
    $fullSuite = Join-Path $RepoA "scripts\Sync-DevTrees.FullSuite.ps1"
    if (!(Test-Path $fullSuite)) {
        Write-Host "[ERROR] FullSuite script missing: $fullSuite" -ForegroundColor Red
        return 97
    }

    Write-Host "`n>>> Running Sync-Dev Apply..." -ForegroundColor Yellow
    & $fullSuite -ForceApply
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ABORT] Sync-Dev Apply failed with code $LASTEXITCODE." -ForegroundColor Red
        return $LASTEXITCODE
    }

    # 4. Final validation
    Write-Host "`n>>> Final validation..." -ForegroundColor Yellow
    Test-ForensicSuiteAll
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ABORT] Final validation failed with code $LASTEXITCODE." -ForegroundColor Red
        return $LASTEXITCODE
    }

    Write-Host "`n[SUCCESS] Workspace repaired successfully (V9.3.4)." -ForegroundColor Green
    return 0
}

# =====================================================================
# 2. PRE-FLIGHT WRAPPER
# =====================================================================

function Invoke-Preflight {
    & (Join-Path $Global:PrimaryRoot "scripts\Invoke-Preflight.ps1")
    return $LASTEXITCODE
}

# =====================================================================
# 3. DEVELOPMENT & SYNC (V9.3.4 ATOMIC SYNC-DEV)
# =====================================================================

function Update-InstallerPayload {
    param(
        [string]$RepoRoot = $Global:PrimaryRoot
    )

    $script = Join-Path $RepoRoot "scripts\refresh_installer_payload.ps1"

    if (!(Test-Path $script)) {
        Write-Host "[ERROR] refresh_installer_payload.ps1 not found at: $script" -ForegroundColor Red
        return 1
    }

    Write-Host ">>> Running Update-InstallerPayload..." -ForegroundColor Yellow
    & $script -Root $RepoRoot -PayloadRoot (Join-Path $RepoRoot "installer_payload")
    return $LASTEXITCODE
}

function Update-ForensicSuiteDev {
    param(
        [switch]$Apply
    )

    $FullSuite = Join-Path $Global:PrimaryRoot "scripts\Sync-DevTrees.FullSuite.ps1"

    if (!(Test-Path $FullSuite)) {
        Write-Host "[ERROR] FullSuite script not found at $FullSuite" -ForegroundColor Red
        return 1
    }

    if ($Apply) {
        Write-Host ">>> Running Sync-Dev FULL APPLY (V9.3.4)..." -ForegroundColor Cyan
        & $FullSuite -ForceApply
    } else {
        Write-Host ">>> Running Sync-Dev DRY RUN (V9.3.4)..." -ForegroundColor Cyan
        & $FullSuite
    }

    return $LASTEXITCODE
}

Set-Alias syncdev Update-ForensicSuiteDev

function Update-ForensicSuiteValidation {
    Write-Host "`n>>> Verifying Mirror Integrity..." -ForegroundColor Cyan
    & (Join-Path $Global:PrimaryRoot "scripts\Sync-DevTrees.Validate.ps1")
    return $LASTEXITCODE
}

# =====================================================================
# 4. INSTALLATION & BUILD
# =====================================================================

function Invoke-BuildSuiteSafe {
    Write-Host "`n>>> Running Clear-ForensicSuiteAll before Invoke-BuildSuite..." -ForegroundColor Cyan
    $clean = Clear-ForensicSuiteAll
    if ($clean -ne 0) {
        Write-Host "[ABORT] Invoke-BuildSuite blocked by Clear-ForensicSuiteAll." -ForegroundColor Red
        return $clean
    }
    Invoke-BuildSuite
}

function Invoke-BuildSuite {
    param(
        [switch]$Force
    )

    $ErrorActionPreference = "Stop"

    # Preflight
    $pre = Invoke-Preflight
    if ($pre -ne 0) {
        Write-Host "[ABORT] Invoke-BuildSuite blocked." -ForegroundColor Red
        return $pre
    }

    # Path anchors
    $RepoRoot  = $Global:PrimaryRoot
    $SuiteRoot = Join-Path $RepoRoot "forensic_suite_v2"

    # Logging
    $LogRoot = Join-Path $SuiteRoot "logs"
    if (-not (Test-Path $LogRoot)) {
        New-Item -ItemType Directory -Path $LogRoot | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile   = Join-Path $LogRoot "BuildSuite_$Timestamp.log"

    function Log {
        param([string]$msg)
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
        Add-Content -Path $LogFile -Value $line
        Write-Host $msg
    }

    Log "=== Invoke-BuildSuite START ==="
    $TotalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # 1. Build wheel + PyInstaller bundle
        Log "[1/5] Building wheel + PyInstaller bundle..."
        & (Join-Path $RepoRoot "build_final.ps1") -BuildOnly
        if ($LASTEXITCODE -ne 0) { return 101 }

        # 2. Refresh installer payload
        Log "[2/5] Refreshing installer_payload..."
        & (Join-Path $RepoRoot "scripts\refresh_installer_payload.ps1") -Root $RepoRoot -PayloadRoot (Join-Path $RepoRoot "installer_payload")
        if ($LASTEXITCODE -ne 0) { return 102 }

        $payloadDir   = Join-Path $RepoRoot "installer_payload"
        $payloadCount = (Get-ChildItem $payloadDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count

        if ($payloadCount -lt 1) {
            Log "[FATAL] installer_payload is empty after refresh: $payloadDir"
            return 102
        }
        Log "[OK] installer_payload file count: $payloadCount"

        # 3. Build installer EXE
        Log "[3/5] Building installer EXE..."
        & (Join-Path $RepoRoot "build_and_deploy.ps1") -BuildOnly
        if ($LASTEXITCODE -ne 0) { return 103 }

        $InstallerExe = Join-Path $RepoRoot "Output\ForensicSuiteV2-Setup.exe"
        if (-not (Test-Path $InstallerExe)) { return 104 }

        # 4. Post-install validation
        Log "[4/5] Running post-install validation..."
        & (Join-Path $RepoRoot "post_install_validation.ps1") -InstallerExe $InstallerExe
        if ($LASTEXITCODE -ne 0) { return 105 }

        # 5. Installer payload integrity validation
        Log "[5/5] Verifying installer payload integrity..."
        & (Join-Path $RepoRoot "scripts\validate_installer_payload.ps1")
        if ($LASTEXITCODE -ne 0) {
            Log "[FAIL] Installer payload validation failed with code $LASTEXITCODE"
            return 106
        }
        Log "[OK] Installer payload validated successfully."

        $TotalTimer.Stop()
        Log "=== Invoke-BuildSuite COMPLETED SUCCESSFULLY ==="
        Log "Total Runtime: $($TotalTimer.Elapsed.ToString())"
        return 0
    }
    catch {
        $TotalTimer.Stop()
        Log "[FATAL] Unhandled exception: $_"
        return 199
    }
}

# =====================================================================
# 5. DEPLOYMENT & SECRETS
# =====================================================================

function Invoke-DeployPreflight {
    $ErrorActionPreference = "Stop"

    Write-Host "`n>>> Running Deploy-Suite Preflight..." -ForegroundColor Cyan

    # 1. Validate installer payload integrity
    $payloadValidator = Join-Path $Global:PrimaryRoot "scripts\validate_installer_payload.ps1"
    if (-not (Test-Path $payloadValidator)) {
        Write-Host "[BLOCKED] Missing validate_installer_payload.ps1" -ForegroundColor Red
        return 201
    }

    & $payloadValidator
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[BLOCKED] Installer payload integrity check failed." -ForegroundColor Red
        return 202
    }
    Write-Host "[OK] Installer payload integrity validated." -ForegroundColor Green

    # 2. Validate installer EXE exists
    $InstallerExe = Join-Path $Global:PrimaryRoot "Output\ForensicSuiteV2-Setup.exe"
    if (-not (Test-Path $InstallerExe)) {
        Write-Host "[BLOCKED] Installer EXE missing: $InstallerExe" -ForegroundColor Red
        return 203
    }
    Write-Host "[OK] Installer EXE found." -ForegroundColor Green

    # 3. Validate deployment scripts exist
    $deployScript = Join-Path $Global:PrimaryRoot "deploy_suite.ps1"
    if (-not (Test-Path $deployScript)) {
        Write-Host "[BLOCKED] Missing deploy_suite.ps1" -ForegroundColor Red
        return 204
    }

    $buildDeploy = Join-Path $Global:PrimaryRoot "build_and_deploy.ps1"
    if (-not (Test-Path $buildDeploy)) {
        Write-Host "[BLOCKED] Missing build_and_deploy.ps1" -ForegroundColor Red
        return 205
    }

    Write-Host "[OK] Deployment scripts validated." -ForegroundColor Green
    Write-Host "[OK] Deploy-Suite Preflight passed." -ForegroundColor Green
    return 0
}

function Get-DeploySuiteSummary {
    $ErrorActionPreference = "Stop"

    Write-Host "`n=== Deploy-Suite Summary Report (V9.3.4) ===" -ForegroundColor Cyan

    $root            = $Global:PrimaryRoot
    $dist            = Join-Path $root "dist"
    $payloadRoot     = Join-Path $root "installer_payload"
    $payloadWheelDir = Join-Path $payloadRoot "wheel"
    $payloadScripts  = Join-Path $payloadRoot "scripts"
    $srcScripts      = Join-Path $root "scripts"
    $installerExe    = Join-Path $root "Output\ForensicSuiteV2-Setup.exe"

    # 1. Wheel Version & Freshness
    Write-Host "`n[1/5] Wheel Version & Freshness" -ForegroundColor Cyan

    $latestSrcWheel = Get-ChildItem $dist -Filter "forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending |
                      Select-Object -First 1

    if ($latestSrcWheel) {
        Write-Host "  Latest built wheel: $($latestSrcWheel.Name)"
    } else {
        Write-Host "  [WARN] No wheel found in dist\" -ForegroundColor Yellow
    }

    $payloadWheel = Get-ChildItem $payloadWheelDir -Filter "forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1

    if ($payloadWheel) {
        Write-Host "  Payload wheel:      $($payloadWheel.Name)"
    } else {
        Write-Host "  [WARN] No wheel found in installer_payload\wheel" -ForegroundColor Yellow
    }

    if ($latestSrcWheel -and $payloadWheel) {
        if ($latestSrcWheel.Name -eq $payloadWheel.Name) {
            Write-Host "  [OK] Wheel is latest." -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] Wheel mismatch." -ForegroundColor Red
        }
    }

    # 2. Payload Hash
    Write-Host "`n[2/5] Payload Hash" -ForegroundColor Cyan

    if (Test-Path $payloadRoot) {
        $payloadHash = Get-ChildItem $payloadRoot -Recurse -File |
                       Get-FileHash -Algorithm SHA256 |
                       Select-Object -ExpandProperty Hash |
                       Out-String
        $payloadHash = $payloadHash.Trim()
        Write-Host "  SHA256 (payload): $payloadHash"
    } else {
        Write-Host "  [WARN] Payload folder missing." -ForegroundColor Yellow
    }

    # 3. Installer EXE Hash
    Write-Host "`n[3/5] Installer EXE Hash" -ForegroundColor Cyan

    if (Test-Path $installerExe) {
        $exeHash = (Get-FileHash $installerExe -Algorithm SHA256).Hash
        Write-Host "  Installer: $installerExe"
        Write-Host "  SHA256:    $exeHash"
    } else {
        Write-Host "  [FAIL] Installer EXE missing." -ForegroundColor Red
    }

    # 4. Script Drift Status
    Write-Host "`n[4/5] Script Drift Status" -ForegroundColor Cyan

    if (-not (Test-Path $payloadScripts)) {
        Write-Host "  [FAIL] installer_payload\scripts missing." -ForegroundColor Red
    } else {
        $srcFiles     = Get-ChildItem $srcScripts -File -Recurse
        $payloadFiles = Get-ChildItem $payloadScripts -File -Recurse

        $missing = @()
        $extra   = @()
        $drift   = @()

        foreach ($src in $srcFiles) {
            $rel  = $src.FullName.Substring($srcScripts.Length).TrimStart("\")
            $dest = Join-Path $payloadScripts $rel

            if (-not (Test-Path $dest)) {
                $missing += $rel
                continue
            }

            $hashA = (Get-FileHash $src.FullName  -Algorithm SHA256).Hash
            $hashB = (Get-FileHash $dest.FullName -Algorithm SHA256).Hash

            if ($hashA -ne $hashB) {
                $drift += $rel
            }
        }

        foreach ($p in $payloadFiles) {
            $rel = $p.FullName.Substring($payloadScripts.Length).TrimStart("\")
            $src = Join-Path $srcScripts $rel

            if (-not (Test-Path $src)) {
                $extra += $rel
            }
        }

        if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $drift.Count -eq 0) {
            Write-Host "  [OK] No script drift detected." -ForegroundColor Green
        } else {
            if ($missing.Count -gt 0) {
                Write-Host "  Missing:" -ForegroundColor Red
                $missing | ForEach-Object { Write-Host "    $_" }
            }
            if ($extra.Count -gt 0) {
                Write-Host "  Extra:" -ForegroundColor Red
                $extra | ForEach-Object { Write-Host "    $_" }
            }
            if ($drift.Count -gt 0) {
                Write-Host "  Drifted:" -ForegroundColor Red
                $drift | ForEach-Object { Write-Host "    $_" }
            }
        }
    }

    # 5. Deployment readiness
    Write-Host "`n[5/5] Deployment Readiness" -ForegroundColor Cyan

    $pre = Invoke-DeployPreflight
    if ($pre -eq 0) {
        Write-Host "  [READY] Deployment can proceed." -ForegroundColor Green
    } else {
        Write-Host "  [BLOCKED] Deployment cannot proceed. Preflight code: $pre" -ForegroundColor Red
    }

    Write-Host "`n=== End of Deploy-Suite Summary Report ===`n" -ForegroundColor Cyan
}

function Invoke-DeployHost {
    param(
        [Parameter(Mandatory = $true)][string]$IP,
        [switch]$BlueGreen
    )

    $pre = Invoke-DeployPreflight
    if ($pre -ne 0) { return $pre }

    $Installer = Join-Path $Global:PrimaryRoot "Output\ForensicSuiteV2-Setup.exe"
    & (Join-Path $Global:PrimaryRoot "deploy_suite.ps1") -TargetHost $IP -InstallerPath $Installer -BlueGreen:$BlueGreen
}

function Invoke-DeployCluster {
    param(
        [switch]$BlueGreen
    )

    $pre = Invoke-DeployPreflight
    if ($pre -ne 0) { return $pre }

    & (Join-Path $Global:PrimaryRoot "build_and_deploy.ps1") -Deploy -BlueGreen:$BlueGreen
}

function Update-ForensicSuiteSecrets {
    Write-Host "`n>>> Provisioning REAL Secrets (env.json) to Cluster..." -ForegroundColor Magenta

    $LocalSecret = Join-Path $Global:PrimaryRoot "env.json"
    if (!(Test-Path $LocalSecret)) {
        Write-Error "CRITICAL: Local env.json missing!"
        return
    }

    foreach ($ip in $Global:ClusterIPs) {
        Write-Host ">>> Patching Node: $ip" -ForegroundColor Cyan
        scp -i $Global:SSHKey "$LocalSecret" "forensicuser@${ip}:F:\forensic_secrets\env.json"
        ssh -i $Global:SSHKey "forensicuser@$ip" "icacls F:\forensic_secrets\env.json /grant SYSTEM:(R)"
    }

    Write-Host "[SUCCESS] All nodes provisioned." -ForegroundColor Green
}

# =====================================================================
# 6. UNINSTALL / RECOVERY
# =====================================================================

function Invoke-ForensicUninstall {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Minimal", "Full")]
        [string]$Mode,
        [string]$TargetHost
    )

    $Hosts = if ($TargetHost) { @($TargetHost) } else { $Global:ClusterIPs }

    Write-Host "`n=== Forensic Suite Uninstall (V9.3.4) ===" -ForegroundColor Cyan
    Write-Host "Mode  : $Mode" -ForegroundColor Gray
    Write-Host "Hosts : $($Hosts -join ', ')" -ForegroundColor Gray

    foreach ($ip in $Hosts) {
        Write-Host "`n>>> Wiping Node $ip..." -ForegroundColor Cyan

        $paths = @(
            "C:\forensic_suite_v2",
            "C:\forensic_suite_v2_blue",
            "C:\forensic_suite_v2_green",
            "C:\forensic_suite_v2_installer.exe"
        )

        $svcCmd = if ($Mode -eq "Full") {
            "Stop-Service btc_indexer, eth_indexer, tron_indexer -Force -ErrorAction SilentlyContinue; " +
            "Set-Service btc_indexer -StartupType Disabled -ErrorAction SilentlyContinue; " +
            "Set-Service eth_indexer -StartupType Disabled -ErrorAction SilentlyContinue; " +
            "Set-Service tron_indexer -StartupType Disabled -ErrorAction SilentlyContinue; "
        } else {
            "Stop-Service btc_indexer, eth_indexer, tron_indexer -Force -ErrorAction SilentlyContinue; "
        }

        $rmCmd = ($paths | ForEach-Object {
                "Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue;"
            }) -join " "

        $cleanCmd = $svcCmd + $rmCmd

        ssh -i $Global:SSHKey "forensicuser@$ip" "powershell -Command `"$cleanCmd`""

        Write-Host "[OK] Node $ip wiped ($Mode)." -ForegroundColor Green
    }

    Write-Host "`n[COMPLETE] Uninstall orchestration finished." -ForegroundColor Green
}

# =====================================================================
# 7. HEALTH & DASHBOARD
# =====================================================================

function Get-StatusReport {
    Write-Host "`n=== FORENSIC SUITE CLUSTER STATUS (V9.3.4) ===" -ForegroundColor Cyan

    foreach ($ip in $Global:ClusterIPs) {

        $ping = if (Test-Connection -ComputerName $ip -Count 1 -Quiet) { "UP" } else { "DOWN" }

        $slot        = "UNKNOWN"
        $disk        = "UNKNOWN"
        $svc_btc     = "UNKNOWN"
        $svc_eth     = "UNKNOWN"
        $svc_tron    = "UNKNOWN"
        $svc_orch    = "UNKNOWN"
        $remoteWheel = "UNKNOWN"
        $remoteHash  = "UNKNOWN"
        $envStatus   = "UNKNOWN"

        if ($ping -eq "UP") {

            # SLOT
            $slot = Invoke-RemotePS -Host $ip -Script @'
if (Test-Path "C:\forensic_suite_v2_blue") { "BLUE" }
elseif (Test-Path "C:\forensic_suite_v2_green") { "GREEN" }
elseif (Test-Path "C:\forensic_suite_v2") { "LEGACY" }
else { "NONE" }
'@

            # BTC
            $svc_btc = Invoke-RemotePS -Host $ip -Script @'
if (Get-Service btc_indexer -ErrorAction SilentlyContinue) {
    (Get-Service btc_indexer).Status
} else {
    "MISSING"
}
'@

            # ETH
            $svc_eth = Invoke-RemotePS -Host $ip -Script @'
if (Get-Service eth_indexer -ErrorAction SilentlyContinue) {
    (Get-Service eth_indexer).Status
} else {
    "MISSING"
}
'@

            # TRON
            $svc_tron = Invoke-RemotePS -Host $ip -Script @'
if (Get-Service tron_indexer -ErrorAction SilentlyContinue) {
    (Get-Service tron_indexer).Status
} else {
    "MISSING"
}
'@

            # ORCHESTRATOR
            $svc_orch = Invoke-RemotePS -Host $ip -Script @'
if (Get-Service forensic_orchestrator -ErrorAction SilentlyContinue) {
    (Get-Service forensic_orchestrator).Status
} else {
    "MISSING"
}
'@

            # DISK
            $disk = Invoke-RemotePS -Host $ip -Script @'
(Get-PSDrive C).Free / 1GB -as [int]
'@

            # WHEEL
            $remoteWheel = Invoke-RemotePS -Host $ip -Script @'
$w = Get-ChildItem "C:\forensic_suite_v2*\installer_payload\wheel\forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
     Sort-Object LastWriteTime -Descending |
     Select-Object -First 1
if ($w) { $w.Name } else { "NONE" }
'@

            # PAYLOAD HASH
            $remoteHash = Invoke-RemotePS -Host $ip -Script @'
if (Test-Path "C:\forensic_suite_v2*\installer_payload") {
    Get-ChildItem "C:\forensic_suite_v2*\installer_payload" -Recurse -File |
    Get-FileHash -Algorithm SHA256 |
    Select-Object -ExpandProperty Hash |
    Out-String
} else {
    "NONE"
}
'@

            # ENV.JSON
            $envStatus = Invoke-RemotePS -Host $ip -Script @'
$envPath = Get-ChildItem "C:\forensic_suite_v2*\config\env.json" -ErrorAction SilentlyContinue
if (-not $envPath) { "MISSING"; return }

try {
    $json = Get-Content $envPath.FullName | ConvertFrom-Json
    if ($json.db_host -and $json.db_user -and $json.db_name) {
        "OK"
    } else {
        "INVALID"
    }
}
catch {
    "INVALID"
}
'@
        }

        $healthy = ($ping -eq "UP") -and
                   ($svc_btc -match "Running") -and
                   ($svc_eth -match "Running") -and
                   ($svc_tron -match "Running") -and
                   ($svc_orch -match "Running") -and
                   ($envStatus -eq "OK")

        $color = if ($healthy) { "Green" }
                 elseif ($ping -eq "UP") { "Yellow" }
                 else { "Red" }

        Write-Host ""
        Write-Host ("  {0}" -f $ip) -ForegroundColor $color
        Write-Host ("     PING:        {0}" -f $ping)
        Write-Host ("     SLOT:        {0}" -f $slot)
        Write-Host ("     BTC:         {0}" -f $svc_btc)
        Write-Host ("     ETH:         {0}" -f $svc_eth)
        Write-Host ("     TRON:        {0}" -f $svc_tron)
        Write-Host ("     ORCH:        {0}" -f $svc_orch)
        Write-Host ("     FREE_C:      {0} GB" -f $disk)
        Write-Host ("     WHEEL:       {0}" -f $remoteWheel)
        Write-Host ("     PAYLOAD HASH:{0}" -f (($remoteHash | Out-String).Trim()))
        Write-Host ("     ENV.JSON:    {0}" -f $envStatus)
    }

    Write-Host "`n=== END CLUSTER STATUS (V9.3.4) ===`n" -ForegroundColor Cyan
}

function Export-StatusReportJson {
    $ErrorActionPreference = "Stop"

    $results = @()

    foreach ($ip in $Global:ClusterIPs) {

        $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet

        $slot        = $null
        $disk        = $null
        $svc_btc     = $null
        $svc_eth     = $null
        $svc_tron    = $null
        $svc_orch    = $null
        $remoteWheel = $null
        $remoteHash  = $null
        $envStatus   = $null

        if ($ping) {
            $slot = Invoke-RemotePS -Host $ip -Script @'
if (Test-Path "C:\forensic_suite_v2_blue") { "BLUE" }
elseif (Test-Path "C:\forensic_suite_v2_green") { "GREEN" }
elseif (Test-Path "C:\forensic_suite_v2") { "LEGACY" }
else { "NONE" }
'@

            $svc_btc = Invoke-RemotePS -Host $ip -Script @'
if (Get-Service btc_indexer -ErrorAction SilentlyContinue) {
    (Get-Service btc_indexer).Status
} else {
    "MISSING"
}
'@

            $svc_eth = Invoke-RemotePS -Host $ip -Script @'
if (Get-Service eth_indexer -ErrorAction SilentlyContinue) {
    (Get-Service eth_indexer).Status
} else {
    "MISSING"
}
'@

            $svc_tron = Invoke-RemotePS -Host $ip -Script @'
if (Get-Service tron_indexer -ErrorAction SilentlyContinue) {
    (Get-Service tron_indexer).Status
} else {
    "MISSING"
}
'@

            $svc_orch = Invoke-RemotePS -Host $ip -Script @'
if (Get-Service forensic_orchestrator -ErrorAction SilentlyContinue) {
    (Get-Service forensic_orchestrator).Status
} else {
    "MISSING"
}
'@

            $disk = Invoke-RemotePS -Host $ip -Script @'
(Get-PSDrive C).Free / 1GB -as [int]
'@

            $remoteWheel = Invoke-RemotePS -Host $ip -Script @'
$w = Get-ChildItem "C:\forensic_suite_v2*\installer_payload\wheel\forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
     Sort-Object LastWriteTime -Descending |
     Select-Object -First 1
if ($w) { $w.Name } else { "NONE" }
'@

            $remoteHash = Invoke-RemotePS -Host $ip -Script @'
if (Test-Path "C:\forensic_suite_v2*\installer_payload") {
    Get-ChildItem "C:\forensic_suite_v2*\installer_payload" -Recurse -File |
    Get-FileHash -Algorithm SHA256 |
    Select-Object -ExpandProperty Hash |
    Out-String
} else {
    "NONE"
}
'@

            $envStatus = Invoke-RemotePS -Host $ip -Script @'
$envPath = Get-ChildItem "C:\forensic_suite_v2*\config\env.json" -ErrorAction SilentlyContinue
if (-not $envPath) { "MISSING"; return }

try {
    $json = Get-Content $envPath.FullName | ConvertFrom-Json
    if ($json.db_host -and $json.db_user -and $json.db_name) {
        "OK"
    } else {
        "INVALID"
    }
}
catch {
    "INVALID"
}
'@
        }

        $results += [PSCustomObject]@{
            Host         = $ip
            Reachable    = $ping
            Slot         = if ($slot) { ($slot | Out-String).Trim() } else { $null }
            DiskFreeGB   = if ($disk) { (($disk | Out-String).Trim()) } else { $null }
            BTC          = if ($svc_btc) { ($svc_btc | Out-String).Trim() } else { $null }
            ETH          = if ($svc_eth) { ($svc_eth | Out-String).Trim() } else { $null }
            TRON         = if ($svc_tron) { ($svc_tron | Out-String).Trim() } else { $null }
            Orchestrator = if ($svc_orch) { ($svc_orch | Out-String).Trim() } else { $null }
            Wheel        = if ($remoteWheel) { ($remoteWheel | Out-String).Trim() } else { $null }
            PayloadHash  = if ($remoteHash) { ($remoteHash | Out-String).Trim() } else { $null }
            EnvStatus    = if ($envStatus) { ($envStatus | Out-String).Trim() } else { $null }
        }
    }

    $results | ConvertTo-Json -Depth 4
}

function Compare-StatusReport {
    param(
        [Parameter(Mandatory = $true)][string]$BaselinePath,
        [Parameter(Mandatory = $true)][string]$CurrentPath
    )

    $baseline = Get-Content $BaselinePath | ConvertFrom-Json
    $current  = Get-Content $CurrentPath  | ConvertFrom-Json

    Write-Host "`n=== STATUS REPORT DIFF (V9.3.4) ===" -ForegroundColor Cyan

    foreach ($b in $baseline) {
        $c = $current | Where-Object { $_.Host -eq $b.Host }
        if (-not $c) {
            Write-Host "Host missing in current: $($b.Host)" -ForegroundColor Yellow
            continue
        }

        $props = "Reachable", "Slot", "DiskFreeGB", "BTC", "ETH", "TRON", "Orchestrator", "Wheel", "EnvStatus"
        foreach ($p in $props) {
            if ($b.$p -ne $c.$p) {
                Write-Host ("[{0}] {1}: {2} -> {3}" -f $b.Host, $p, $b.$p, $c.$p) -ForegroundColor Yellow
            }
        }
    }

    Write-Host "`n=== END STATUS REPORT DIFF ===" -ForegroundColor Cyan
}

# =====================================================================
# 8. ALIASES & EXPORTS
# =====================================================================

Set-Alias cleanall   Clear-ForensicSuiteAll
Set-Alias restore    Restore-Workspace
Set-Alias safe-build Invoke-BuildSuiteSafe
Set-Alias payloadfix Update-InstallerPayload
Set-Alias syncdev    Update-ForensicSuiteDev
Set-Alias validate   Test-ForensicSuiteAll

Export-ModuleMember -Function `
    Clear-ForensicSuiteAll, `
    Compare-StatusReport, `
    Export-StatusReportJson, `
    Get-DeploySuiteSummary, `
    Get-ForensicSuiteHelp, `
    Get-StatusReport, `
    Invoke-BuildSuite, `
    Invoke-BuildSuiteSafe, `
    Invoke-DeployCluster, `
    Invoke-DeployHost, `
    Invoke-DeployPreflight, `
    Invoke-ForensicUninstall, `
    Invoke-Preflight, `
    Update-InstallerPayload, `
    Restore-Workspace, `
    Test-ForensicSuiteAll, `
    Update-ForensicSuiteDev, `
    Update-ForensicSuiteSecrets, `
    Update-ForensicSuiteValidation

Export-ModuleMember -Alias `
    cleanall, `
    payloadfix, `
    restore, `
    safe-build, `
    syncdev, `
    validate

# =====================================================================
# MODULE INITIALIZATION (prints banner on import)
# =====================================================================

Write-Host ""
Write-Host "Forensic Suite Workspace V9.3.4 Loaded." -ForegroundColor Cyan
Write-Host ""
Write-Host "Modules Imported:" -ForegroundColor Yellow
(Get-Command -Module ForensicSuite.Validation -CommandType Function |
    Sort-Object Name |
    Select-Object -ExpandProperty Name) |
    ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Quick Options:" -ForegroundColor Yellow
Write-Host "  Get-ForensicSuiteHelp   (paged help overview)"
Write-Host "  Invoke-BuildSuiteSafe   (clean + deterministic full build)"
Write-Host "  Get-StatusReport        (runtime / cluster health report)"
Write-Host ""
Write-Host "Convenience aliases:" -ForegroundColor Yellow
Write-Host "  cleanall"
Write-Host "  payloadfix"
Write-Host "  restore"
Write-Host "  safe-build"
Write-Host "  syncdev"
Write-Host "  validate"
Write-Host ""
