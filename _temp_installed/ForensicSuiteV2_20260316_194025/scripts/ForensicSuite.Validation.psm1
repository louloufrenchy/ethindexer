# =====================================================================
# ForensicSuite.Validation.psm1 (V9.3.5)
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

function Ensure-NSSMRemote {
    param(
        [Parameter(Mandatory = $true)][string]$Host
    )

    $sshExe = "$env:WINDIR\System32\OpenSSH\ssh.exe"
    $scpExe = "$env:WINDIR\System32\OpenSSH\scp.exe"

    $LocalNssmExe  = Join-Path $Global:PrimaryRoot "third_party\nssm\nssm.exe"
    $RemoteNssmDir = "F:\tools\nssm"
    $RemoteNssmExe = "F:\tools\nssm\nssm.exe"

    if (-not (Test-Path $LocalNssmExe)) {
        Write-Host "[ERROR] NSSM binary missing from Repo A: $LocalNssmExe" -ForegroundColor Red
        return 901
    }

    Write-Host ">>> Ensuring NSSM on $Host ..." -ForegroundColor Cyan

    $mkdirResult = Invoke-RemotePS -Host $Host -Script @"
New-Item -ItemType Directory -Path '$RemoteNssmDir' -Force | Out-Null
if (Test-Path '$RemoteNssmExe') { 'PRESENT' } else { 'ABSENT' }
"@

    if ($mkdirResult -eq "SSH_ERROR") {
        Write-Host "[ERROR] SSH failed while preparing NSSM directory on $Host" -ForegroundColor Red
        return 902
    }

    if ($mkdirResult -match "PRESENT") {
        Write-Host "[OK] NSSM already present on $Host" -ForegroundColor Green
        return 0
    }

    & $scpExe `
        -i $Global:SSHKey `
        "$LocalNssmExe" `
        "forensicuser@${Host}:F:/tools/nssm/nssm.exe" `
        2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] SCP failed while copying NSSM to $Host" -ForegroundColor Red
        return 903
    }

    $verifyResult = Invoke-RemotePS -Host $Host -Script @"
if (Test-Path '$RemoteNssmExe') { 'OK' } else { 'MISSING' }
"@

    if ($verifyResult -eq "SSH_ERROR") {
        Write-Host "[ERROR] SSH failed while verifying NSSM on $Host" -ForegroundColor Red
        return 904
    }

    if ($verifyResult -notmatch "OK") {
        Write-Host "[ERROR] NSSM verification failed on $Host" -ForegroundColor Red
        return 905
    }

    Write-Host "[OK] NSSM staged on $Host" -ForegroundColor Green
    return 0
}

function Invoke-ForensicRelease {
    [CmdletBinding()]
    param(
        [switch]$BuildOnly,
        [switch]$DeployOnly,
        [switch]$SkipClean,
        [switch]$SkipPayloadRefresh,
        [switch]$SkipStatusReport,
        [switch]$SkipPostBuildValidation,
        [switch]$BlueGreen,
        [switch]$EnableRollback,
        [string[]]$Hosts
    )

    $scriptPath = Join-Path $Global:PrimaryRoot "scripts\Invoke-ForensicRelease.ps1"

    if (-not (Test-Path $scriptPath)) {
        Write-Host "[ERROR] Invoke-ForensicRelease.ps1 not found at: $scriptPath" -ForegroundColor Red
        return 1
    }

    # Stage NSSM to remote hosts only for deploy workflows
    if ($DeployOnly -or (-not $BuildOnly)) {
        $targetHosts = @($Hosts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        if ($targetHosts.Count -gt 0) {
            foreach ($hostName in $targetHosts) {
                $nssmCode = Ensure-NSSMRemote -Host $hostName
                if ($nssmCode -ne 0) {
                    Write-Host "[ABORT] Deploy blocked because NSSM staging failed on $hostName (code $nssmCode)." -ForegroundColor Red
                    return $nssmCode
                }
            }
        }
    }

    & $scriptPath `
        -BuildOnly:$BuildOnly `
        -DeployOnly:$DeployOnly `
        -SkipClean:$SkipClean `
        -SkipPayloadRefresh:$SkipPayloadRefresh `
        -SkipStatusReport:$SkipStatusReport `
        -SkipPostBuildValidation:$SkipPostBuildValidation `
        -BlueGreen:$BlueGreen `
        -EnableRollback:$EnableRollback `
        -Hosts @($Hosts)

    return $LASTEXITCODE
}

# =====================================================================
# 2. PRE-FLIGHT WRAPPER
# =====================================================================

function Invoke-Preflight {
    [CmdletBinding()]
    param()

    $scriptPath = Join-Path $Global:PrimaryRoot "scripts\Invoke-Preflight.ps1"

    if (-not (Test-Path $scriptPath)) {
        Write-Host "[ERROR] Invoke-Preflight.ps1 not found at: $scriptPath" -ForegroundColor Red
        return 98
    }

    $global:LASTEXITCODE = 0

    # Capture any pipeline output without letting it corrupt exit-code handling
    $result = & $scriptPath 2>&1
    $exitCode = $LASTEXITCODE

    if ($null -eq $exitCode) {
        $exitCode = 0
    }

    # If the script emitted output objects, do not treat them as return codes
    if ($result) {
        foreach ($line in @($result)) {
            if ($line -is [System.Management.Automation.ErrorRecord]) {
                Write-Host $line.ToString() -ForegroundColor Red
            }
            else {
                Write-Host $line
            }
        }
    }

    return ([int]$exitCode)
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

    foreach ($ip in $Global:ClusterIPs) {
        Write-Host ">>> Deploying to $ip..." -ForegroundColor Cyan
        & (Join-Path $Global:PrimaryRoot "deploy_suite.ps1") `
            -TargetHost $ip `
            -InstallerPath (Join-Path $Global:PrimaryRoot "Output\ForensicSuiteV2-Setup.exe") `
            -BlueGreen:$BlueGreen
    }
}

function Update-ForensicSuiteSecrets {
    [CmdletBinding()]
    param()

    Write-Host "`n>>> Provisioning REAL Secrets (env.json) to Cluster..." -ForegroundColor Magenta

    $SecretRoot = if ($Global:SecretRoot) { $Global:SecretRoot } else { "F:\forensic_secrets" }
    $LocalSecret = Join-Path $SecretRoot "env.json"

    if (-not (Test-Path $LocalSecret)) {
        Write-Error "CRITICAL: Local env.json missing at $LocalSecret"
        return 1
    }

    foreach ($ip in $Global:ClusterIPs) {
        Write-Host ">>> Patching Node: $ip" -ForegroundColor Cyan

        $prepScript = @'
$secretDir = "F:\forensic_secrets"
if (-not (Test-Path $secretDir)) {
    New-Item -ItemType Directory -Path $secretDir -Force | Out-Null
}
'@

        Invoke-RemotePS -Host $ip -Script $prepScript | Out-Null

        & scp -i $Global:SSHKey "$LocalSecret" "forensicuser@${ip}:F:\forensic_secrets\env.json"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to copy env.json to $ip"
            return 2
        }

        $aclScript = @'
$envFile = "F:\forensic_secrets\env.json"
if (-not (Test-Path $envFile)) {
    throw "env.json missing after copy"
}
icacls $envFile /inheritance:r | Out-Null
icacls $envFile /grant:r "SYSTEM:(R)" | Out-Null
icacls $envFile /grant:r "Administrators:(R)" | Out-Null
icacls $envFile /grant:r "forensicuser:(R)" | Out-Null
"OK"
'@

        $aclResult = Invoke-RemotePS -Host $ip -Script $aclScript
        if (($aclResult | Out-String).Trim() -notmatch "^OK$") {
            Write-Warning "ACL update may not have completed cleanly on $ip"
        }
    }

    Write-Host "[SUCCESS] All nodes provisioned from $LocalSecret." -ForegroundColor Green
    return 0
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

    $Hosts = if ($TargetHost) { @($TargetHost) } else { @($Global:ClusterIPs) }

    Write-Host "`n=== Forensic Suite Uninstall (V9.3.8) ===" -ForegroundColor Cyan
    Write-Host "Mode  : $Mode" -ForegroundColor Gray
    Write-Host "Hosts : $($Hosts -join ', ')" -ForegroundColor Gray

    foreach ($ip in $Hosts) {
        Write-Host "`n>>> Wiping Node $ip..." -ForegroundColor Cyan

        $remoteScript = if ($Mode -eq "Full") {
@'
$ErrorActionPreference = "SilentlyContinue"

function Get-LockingPids {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $handleExe = "F:\tools\handle\handle.exe"
    if (-not (Test-Path $handleExe)) {
        return @()
    }

    $lines = & $handleExe -accepteula $Path 2>$null
    if (-not $lines) {
        return @()
    }

    $pids = New-Object System.Collections.Generic.HashSet[int]

    foreach ($line in $lines) {
        if ($line -match 'pid:\s+(\d+)') {
            [void]$pids.Add([int]$matches[1])
        }
    }

    return @($pids)
}

function Stop-LockingProcesses {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $pids = Get-LockingPids -Path $Path
    if (-not $pids -or $pids.Count -eq 0) {
        return @()
    }

    $stopped = @()

    foreach ($pid in $pids) {
        try {
            if ($pid -and $pid -ne $PID) {
                $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-Output ("KILLING_PID={0} NAME={1} PATH={2}" -f $proc.Id, $proc.ProcessName, $Path)
                    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                    $stopped += $pid
                }
            }
        }
        catch {
        }
    }

    Start-Sleep -Seconds 2
    return $stopped
}

function Remove-PathHard {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Retries = 5,
        [int]$DelaySeconds = 2,
        [switch]$ForceHandleCleanup
    )

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            if (Test-Path $Path) {
                $item = Get-Item $Path -Force -ErrorAction SilentlyContinue

                if ($item -and $item.PSIsContainer) {
                    cmd /c "takeown /F "$Path" /R /D Y" 2>$null | Out-Null
                    cmd /c "icacls "$Path" /grant %USERNAME%:F /T /C" 2>$null | Out-Null
                    cmd /c "attrib -r -s -h "$Path" /S /D" 2>$null | Out-Null
                    cmd /c "rmdir /s /q "$Path"" 2>$null | Out-Null
                }
                else {
                    attrib -r -s -h $Path 2>$null | Out-Null
                    Remove-Item $Path -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
        }

        Start-Sleep -Seconds $DelaySeconds

        if (-not (Test-Path $Path)) {
            return $true
        }

        if ($ForceHandleCleanup) {
            Write-Output "HANDLE_SCAN=$Path"
            $null = Stop-LockingProcesses -Path $Path

            try {
                if (Test-Path $Path) {
                    $item = Get-Item $Path -Force -ErrorAction SilentlyContinue

                    if ($item -and $item.PSIsContainer) {
                        cmd /c "takeown /F "$Path" /R /D Y" 2>$null | Out-Null
                        cmd /c "icacls "$Path" /grant %USERNAME%:F /T /C" 2>$null | Out-Null
                        cmd /c "attrib -r -s -h "$Path" /S /D" 2>$null | Out-Null
                        cmd /c "rmdir /s /q "$Path"" 2>$null | Out-Null
                    }
                    else {
                        attrib -r -s -h $Path 2>$null | Out-Null
                        Remove-Item $Path -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            catch {
            }

            Start-Sleep -Seconds $DelaySeconds

            if (-not (Test-Path $Path)) {
                return $true
            }
        }
    }

    return (-not (Test-Path $Path))
}

$handleExe = "F:\tools\handle\handle.exe"
if (Test-Path $handleExe) {
    Write-Output "HANDLE_TOOL=AVAILABLE"
}
else {
    Write-Output "HANDLE_TOOL=MISSING"
}

$services = @(
    "btc_indexer",
    "eth_indexer",
    "tron_indexer",
    "forensic_orchestrator"
)

foreach ($svc in $services) {
    try { Stop-Service $svc -Force -ErrorAction SilentlyContinue } catch {}
    try { Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
}

Start-Sleep -Seconds 3

foreach ($svc in $services) {
    try { sc.exe delete $svc | Out-Null } catch {}
}

Start-Sleep -Seconds 5

# Remove runtime link first
try {
    if (Test-Path "C:\forensic_suite_v2") {
        cmd /c rmdir C:\forensic_suite_v2 2>$null | Out-Null
    }
}
catch {}

Start-Sleep -Seconds 2

$paths = @(
    "C:\forensic_suite_v2_blue",
    "C:\forensic_suite_v2_green",
    "C:\forensic_suite_v2_installer.exe",
    "C:\forensic_suite_logs",
    "C:\forensic_state"
)

$failures = @()

foreach ($p in $paths) {
    Write-Output "REMOVING=$p"
    $ok = Remove-PathHard -Path $p -Retries 5 -DelaySeconds 2 -ForceHandleCleanup
    if (-not $ok) {
        $failures += $p
    }
}

if ($failures.Count -gt 0) {
    "UNINSTALL_PARTIAL"
    $failures | ForEach-Object { "FAILED_PATH=$_"}
}
else {
    "UNINSTALL_OK"
}
'@
        }
        else {
@'
$ErrorActionPreference = "SilentlyContinue"

function Remove-PathHard {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Retries = 3,
        [int]$DelaySeconds = 2
    )

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            if (Test-Path $Path) {
                $item = Get-Item $Path -Force -ErrorAction SilentlyContinue

                if ($item -and $item.PSIsContainer) {
                    cmd /c "takeown /F "$Path" /R /D Y" 2>$null | Out-Null
                    cmd /c "icacls "$Path" /grant %USERNAME%:F /T /C" 2>$null | Out-Null
                    cmd /c "attrib -r -s -h "$Path" /S /D" 2>$null | Out-Null
                    cmd /c "rmdir /s /q "$Path"" 2>$null | Out-Null
                }
                else {
                    attrib -r -s -h $Path 2>$null | Out-Null
                    Remove-Item $Path -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
        }

        Start-Sleep -Seconds $DelaySeconds

        if (-not (Test-Path $Path)) {
            return $true
        }
    }

    return (-not (Test-Path $Path))
}

$services = @(
    "btc_indexer",
    "eth_indexer",
    "tron_indexer",
    "forensic_orchestrator"
)

foreach ($svc in $services) {
    try { Stop-Service $svc -Force -ErrorAction SilentlyContinue } catch {}
}

Start-Sleep -Seconds 2

try {
    if (Test-Path "C:\forensic_suite_v2") {
        cmd /c rmdir C:\forensic_suite_v2 2>$null | Out-Null
    }
}
catch {}

$paths = @(
    "C:\forensic_suite_v2_blue",
    "C:\forensic_suite_v2_green",
    "C:\forensic_suite_v2_installer.exe"
)

$failures = @()

foreach ($p in $paths) {
    Write-Output "REMOVING=$p"
    $ok = Remove-PathHard -Path $p -Retries 3 -DelaySeconds 2
    if (-not $ok) {
        $failures += $p
    }
}

if ($failures.Count -gt 0) {
    "UNINSTALL_PARTIAL"
    $failures | ForEach-Object { "FAILED_PATH=$_"}
}
else {
    "UNINSTALL_OK"
}
'@
        }

        $bytes   = [System.Text.Encoding]::Unicode.GetBytes($remoteScript)
        $encoded = [Convert]::ToBase64String($bytes)

        $result = & "$env:WINDIR\System32\OpenSSH\ssh.exe" `
            -i $Global:SSHKey `
            "forensicuser@$ip" `
            "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded" `
            2>$null

        $text = ($result | Out-String).Trim()

        if ($LASTEXITCODE -ne 0) {
            Write-Host "[FAIL] Node $ip uninstall failed." -ForegroundColor Red
            continue
        }

        if ($text -match "UNINSTALL_PARTIAL") {
            Write-Host "[WARN] Node $ip partially wiped ($Mode)." -ForegroundColor Yellow
            ($text -split "`r?`n" | Where-Object { $_ -like 'FAILED_PATH=*' }) |
                ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        }
        else {
            Write-Host "[OK] Node $ip wiped ($Mode)." -ForegroundColor Green
        }
    }

    Write-Host "`n[COMPLETE] Uninstall orchestration finished." -ForegroundColor Green
}

# =====================================================================
# 7. HEALTH & DASHBOARD
# =====================================================================

function Get-StatusReport {
    [CmdletBinding()]
    param()

    Write-Host "`n=== FORENSIC SUITE CLUSTER STATUS (V9.3.5) ===" -ForegroundColor Cyan

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
            $slot = (Invoke-RemotePS -Host $ip -Script @'
if (Test-Path "C:\forensic_suite_v2_blue") { "BLUE" }
elseif (Test-Path "C:\forensic_suite_v2_green") { "GREEN" }
elseif (Test-Path "C:\forensic_suite_v2") { "LEGACY" }
else { "NONE" }
'@ | Out-String).Trim()

            # BTC
            $svc_btc = (Invoke-RemotePS -Host $ip -Script @'
if (Get-Service btc_indexer -ErrorAction SilentlyContinue) {
    (Get-Service btc_indexer).Status
} else {
    "MISSING"
}
'@ | Out-String).Trim()

            # ETH
            $svc_eth = (Invoke-RemotePS -Host $ip -Script @'
if (Get-Service eth_indexer -ErrorAction SilentlyContinue) {
    (Get-Service eth_indexer).Status
} else {
    "MISSING"
}
'@ | Out-String).Trim()

            # TRON
            $svc_tron = (Invoke-RemotePS -Host $ip -Script @'
if (Get-Service tron_indexer -ErrorAction SilentlyContinue) {
    (Get-Service tron_indexer).Status
} else {
    "MISSING"
}
'@ | Out-String).Trim()

            # ORCHESTRATOR
            $svc_orch = (Invoke-RemotePS -Host $ip -Script @'
if (Get-Service forensic_orchestrator -ErrorAction SilentlyContinue) {
    (Get-Service forensic_orchestrator).Status
} else {
    "MISSING"
}
'@ | Out-String).Trim()

            # DISK
            $disk = (Invoke-RemotePS -Host $ip -Script @'
(Get-PSDrive C).Free / 1GB -as [int]
'@ | Out-String).Trim()

            # WHEEL
            $remoteWheel = (Invoke-RemotePS -Host $ip -Script @'
$w = Get-ChildItem "C:\forensic_suite_v2*\installer_payload\wheel\forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
     Sort-Object LastWriteTime -Descending |
     Select-Object -First 1
if ($w) { $w.Name } else { "NONE" }
'@ | Out-String).Trim()

            # PAYLOAD HASH
            $remoteHash = (Invoke-RemotePS -Host $ip -Script @'
if (Test-Path "C:\forensic_suite_v2*\installer_payload") {
    Get-ChildItem "C:\forensic_suite_v2*\installer_payload" -Recurse -File |
    Get-FileHash -Algorithm SHA256 |
    Select-Object -ExpandProperty Hash |
    Out-String
} else {
    "NONE"
}
'@ | Out-String).Trim()

            # ENV.JSON - now aligned to F:\forensic_secrets
            $envStatus = (Invoke-RemotePS -Host $ip -Script @'
$envFile = "F:\forensic_secrets\env.json"

if (-not (Test-Path $envFile)) {
    "MISSING"
    return
}

try {
    $json = Get-Content $envFile -Raw | ConvertFrom-Json

    # accept presence + valid JSON as baseline
    if ($null -eq $json) {
        "INVALID"
        return
    }

    # flexible schema recognition
    $hostValue = @($json.db_host, $json.host, $json.database_host, $json.postgres_host) | Where-Object { $_ } | Select-Object -First 1
    $userValue = @($json.db_user, $json.user, $json.username, $json.postgres_user) | Where-Object { $_ } | Select-Object -First 1
    $nameValue = @($json.db_name, $json.database, $json.database_name, $json.postgres_db) | Where-Object { $_ } | Select-Object -First 1

    if ($hostValue -or $userValue -or $nameValue) {
        "OK"
    }
    else {
        # valid JSON exists, but schema is not one of the expected sets
        "PRESENT"
    }
}
catch {
    "INVALID"
}
'@ | Out-String).Trim()
        }

        $healthy = ($ping -eq "UP") -and
                   ($svc_btc  -match "Running") -and
                   ($svc_eth  -match "Running") -and
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
        Write-Host ("     PAYLOAD HASH:{0}" -f $remoteHash)
        Write-Host ("     ENV.JSON:    {0}" -f $envStatus)
    }

    Write-Host "`n=== END CLUSTER STATUS (V9.3.5) ===`n" -ForegroundColor Cyan
}

function Export-StatusReportJson {
    [CmdletBinding()]
    param()

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
            $slot = (Invoke-RemotePS -Host $ip -Script @'
if (Test-Path "C:\forensic_suite_v2_blue") { "BLUE" }
elseif (Test-Path "C:\forensic_suite_v2_green") { "GREEN" }
elseif (Test-Path "C:\forensic_suite_v2") { "LEGACY" }
else { "NONE" }
'@ | Out-String).Trim()

            $svc_btc = (Invoke-RemotePS -Host $ip -Script @'
if (Get-Service btc_indexer -ErrorAction SilentlyContinue) {
    (Get-Service btc_indexer).Status
} else {
    "MISSING"
}
'@ | Out-String).Trim()

            $svc_eth = (Invoke-RemotePS -Host $ip -Script @'
if (Get-Service eth_indexer -ErrorAction SilentlyContinue) {
    (Get-Service eth_indexer).Status
} else {
    "MISSING"
}
'@ | Out-String).Trim()

            $svc_tron = (Invoke-RemotePS -Host $ip -Script @'
if (Get-Service tron_indexer -ErrorAction SilentlyContinue) {
    (Get-Service tron_indexer).Status
} else {
    "MISSING"
}
'@ | Out-String).Trim()

            $svc_orch = (Invoke-RemotePS -Host $ip -Script @'
if (Get-Service forensic_orchestrator -ErrorAction SilentlyContinue) {
    (Get-Service forensic_orchestrator).Status
} else {
    "MISSING"
}
'@ | Out-String).Trim()

            $disk = (Invoke-RemotePS -Host $ip -Script @'
(Get-PSDrive C).Free / 1GB -as [int]
'@ | Out-String).Trim()

            $remoteWheel = (Invoke-RemotePS -Host $ip -Script @'
$w = Get-ChildItem "C:\forensic_suite_v2*\installer_payload\wheel\forensic_suite_v2-*.whl" -ErrorAction SilentlyContinue |
     Sort-Object LastWriteTime -Descending |
     Select-Object -First 1
if ($w) { $w.Name } else { "NONE" }
'@ | Out-String).Trim()

            $remoteHash = (Invoke-RemotePS -Host $ip -Script @'
if (Test-Path "C:\forensic_suite_v2*\installer_payload") {
    Get-ChildItem "C:\forensic_suite_v2*\installer_payload" -Recurse -File |
    Get-FileHash -Algorithm SHA256 |
    Select-Object -ExpandProperty Hash |
    Out-String
} else {
    "NONE"
}
'@ | Out-String).Trim()

            $envStatus = (Invoke-RemotePS -Host $ip -Script @'
$envFile = "F:\forensic_secrets\env.json"

if (-not (Test-Path $envFile)) {
    "MISSING"
    return
}

try {
    $json = Get-Content $envFile -Raw | ConvertFrom-Json

    # accept presence + valid JSON as baseline
    if ($null -eq $json) {
        "INVALID"
        return
    }

    # flexible schema recognition
    $hostValue = @($json.db_host, $json.host, $json.database_host, $json.postgres_host) | Where-Object { $_ } | Select-Object -First 1
    $userValue = @($json.db_user, $json.user, $json.username, $json.postgres_user) | Where-Object { $_ } | Select-Object -First 1
    $nameValue = @($json.db_name, $json.database, $json.database_name, $json.postgres_db) | Where-Object { $_ } | Select-Object -First 1

    if ($hostValue -or $userValue -or $nameValue) {
        "OK"
    }
    else {
        # valid JSON exists, but schema is not one of the expected sets
        "PRESENT"
    }
}
catch {
    "INVALID"
}
'@ | Out-String).Trim()
        }

        $results += [PSCustomObject]@{
            Host         = $ip
            Reachable    = $ping
            Slot         = $slot
            DiskFreeGB   = $disk
            BTC          = $svc_btc
            ETH          = $svc_eth
            TRON         = $svc_tron
            Orchestrator = $svc_orch
            Wheel        = $remoteWheel
            PayloadHash  = $remoteHash
            EnvStatus    = $envStatus
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
Set-Alias deploy-suite Invoke-ForensicRelease

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
	Invoke-ForensicRelease, `
    Invoke-Preflight, `
    Update-InstallerPayload, `
    Restore-Workspace, `
    Test-ForensicSuiteAll, `
    Update-ForensicSuiteDev, `
    Update-ForensicSuiteSecrets, `
    Update-ForensicSuiteValidation

Export-ModuleMember -Alias `
    cleanall, `
	deploy-suite, `
    payloadfix, `
    restore, `
    safe-build, `
    syncdev, `
    validate,

# =====================================================================
# MODULE INITIALIZATION (prints banner on import)
# =====================================================================

Write-Host ""
Write-Host "Forensic Suite Workspace V9.3.5 Loaded." -ForegroundColor Cyan
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
Write-Host "  Invoke-ForensicRelease  (full wotkflow deployment)"
Write-Host ""
Write-Host "Convenience aliases:" -ForegroundColor Yellow
Write-Host "  cleanall"
Write-Host "  deploy-suite"
Write-Host "  payloadfix"
Write-Host "  restore"
Write-Host "  safe-build"
Write-Host "  syncdev"
Write-Host "  validate"
Write-Host ""
