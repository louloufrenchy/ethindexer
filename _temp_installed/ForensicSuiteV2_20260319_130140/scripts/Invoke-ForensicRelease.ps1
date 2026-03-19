<#
.SYNOPSIS
    Deterministic one-command build and cluster deployment for Forensic Suite.
	FILE: Invoke-ForensicRelease.ps1

.DESCRIPTION
    Orchestrates the full release pipeline from the control host:
      1. Preflight validation
      2. Optional runtime-mirror cleanup
      3. Build suite artifacts
      4. Optional installer payload refresh
      5. Deploy preflight validation
      6. Deploy to one or more hosts
      7. Final cluster status report
      8. Optional rollback on failure

    Intended to be called from the control host only.

.PARAMETER BuildOnly
    Run build phases only. Do not deploy.

.PARAMETER DeployOnly
    Skip build phases and deploy the current validated installer/payload only.

.PARAMETER SkipClean
    Skip Clear-ForensicSuiteAll before build.

.PARAMETER SkipPayloadRefresh
    Skip explicit Update-InstallerPayload after build.
    Note: Invoke-BuildSuite may already refresh the payload internally.

.PARAMETER SkipStatusReport
    Skip final Get-StatusReport output.

.PARAMETER SkipPostBuildValidation
    Skip Invoke-DeployPreflight before deployment.

.PARAMETER BlueGreen
    Pass Blue/Green deployment mode to deployment commands.

.PARAMETER EnableRollback
    Attempt rollback if deployment fails after deployment has started.

.PARAMETER Hosts
    One or more target hosts. Defaults to $Global:ClusterIPs.

.PARAMETER ProjectRoot
    Override project root. Defaults to $Global:PrimaryRoot.
#>

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
    [string[]]$Hosts,
    [string]$ProjectRoot = $Global:PrimaryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

function Write-Stage {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Abort {
    param([string]$Message)
    Write-Host "[ABORT] $Message" -ForegroundColor Red
}

function Resolve-ReleaseHosts {
    param([string[]]$RequestedHosts)

    $requested = @($RequestedHosts) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if (@($requested).Count -gt 0) {
        return @($requested)
    }

    $cluster = @($Global:ClusterIPs) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if (@($cluster).Count -gt 0) {
        return @($cluster)
    }

    throw "No target hosts supplied and `$Global:ClusterIPs is empty."
}

function Assert-ModuleCommand {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not available in the current session."
    }
}

function Invoke-ReleaseRollback {
    param(
        [string[]]$RollbackHosts,
        [switch]$RollbackBlueGreen
    )

    Write-Stage "Rollback"
    Write-Warn "Rollback requested due to deployment failure."

    if (-not (Get-Command Invoke-RemotePS -ErrorAction SilentlyContinue)) {
        Write-Warn "Invoke-RemotePS not available; rollback skipped."
        return
    }

    foreach ($host in $RollbackHosts) {
        try {
            Write-Info "Attempting rollback on $host ..."

            $rollbackResult = Invoke-RemotePS -Host $host -Script @'
$ErrorActionPreference = "Stop"

$blue  = "C:\forensic_suite_v2_blue"
$green = "C:\forensic_suite_v2_green"
$link  = "C:\forensic_suite_v2"

$target = $null

if ((Test-Path $blue) -and (Test-Path $green)) {
    if (Test-Path $link) {
        try {
            $resolved = (Get-Item $link -Force).Target
            if ($resolved -eq $green) {
                $target = $blue
            }
            elseif ($resolved -eq $blue) {
                $target = $green
            }
        }
        catch {
            $target = $null
        }
    }
}

if (-not $target) {
    "ROLLBACK_SKIPPED"
    return
}

cmd /c rmdir C:\forensic_suite_v2 2>$null | Out-Null
cmd /c mklink /D C:\forensic_suite_v2 $target | Out-Null

"ROLLBACK_OK"
'@

            $rollbackText = (($rollbackResult | Out-String).Trim())

            if ($rollbackText -match "ROLLBACK_OK") {
                Write-Ok "Rollback completed on $host."
            }
            elseif ($rollbackText -match "ROLLBACK_SKIPPED") {
                Write-Warn "Rollback skipped on $host (no clear alternate slot found)."
            }
            else {
                Write-Warn ("Rollback returned unexpected result on {0}: {1}" -f $host, $rollbackText)
            }
        }
        catch {
            Write-Warn "Rollback failed on $(host): $($_.Exception.Message)"
        }
    }
}

function Invoke-RemoteRuntimePrepare {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host
    )

    Write-Host ">>> Preparing runtime on $Host ..." -ForegroundColor Cyan

    $script = @"
`$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-FirstExistingPath {
    param(
        [Parameter(Mandatory = `$true)]
        [string[]]`$Candidates
    )

    foreach (`$candidate in `$Candidates) {
        if (-not [string]::IsNullOrWhiteSpace(`$candidate) -and (Test-Path `$candidate)) {
            return `$candidate
        }
    }

    return `$null
}

`$PythonExe = 'C:\Program Files\Python314\python.exe'
if (-not (Test-Path `$PythonExe)) {
    throw 'Python executable not found at C:\Program Files\Python314\python.exe'
}

# ------------------------------------------------------------------
# Resolve active suite roots
# ------------------------------------------------------------------
`$SuiteRootCandidates = @(
    'C:\forensic_suite_v2',
    'C:\forensic_suite_v2_blue',
    'C:\forensic_suite_v2_green'
)

`$SuiteRoot = Resolve-FirstExistingPath -Candidates `$SuiteRootCandidates
if (-not `$SuiteRoot) {
    throw 'No suite root found under C:\forensic_suite_v2, C:\forensic_suite_v2_blue, or C:\forensic_suite_v2_green'
}

# ------------------------------------------------------------------
# Ensure base runtime directories
# ------------------------------------------------------------------
New-Item -ItemType Directory -Path 'C:\forensic_state' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\forensic_state\btc' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\forensic_state\eth' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\forensic_state\tron' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\forensic_suite_logs' -Force | Out-Null

# ------------------------------------------------------------------
# Resolve authoritative scripts
# ------------------------------------------------------------------
`$InstallIndexerHostCandidates = @(
    (Join-Path `$SuiteRoot 'scripts\install\Install-IndexerHost.ps1'),
    'C:\forensic_suite_v2\scripts\install\Install-IndexerHost.ps1',
    'C:\forensic_suite_v2_blue\scripts\install\Install-IndexerHost.ps1',
    'C:\forensic_suite_v2_green\scripts\install\Install-IndexerHost.ps1'
)

`$InstallServicesCandidates = @(
    (Join-Path `$SuiteRoot 'forensic_suite_v2\scripts\install_services.ps1'),
    'C:\forensic_suite_v2\forensic_suite_v2\scripts\install_services.ps1',
    'C:\forensic_suite_v2_blue\forensic_suite_v2\scripts\install_services.ps1',
    'C:\forensic_suite_v2_green\forensic_suite_v2\scripts\install_services.ps1'
)

`$InstallIndexerHostPs1 = Resolve-FirstExistingPath -Candidates `$InstallIndexerHostCandidates
`$InstallServicesPs1    = Resolve-FirstExistingPath -Candidates `$InstallServicesCandidates

if (-not `$InstallIndexerHostPs1) {
    throw ('Install-IndexerHost.ps1 not found. Checked: ' + ((`$InstallIndexerHostCandidates) -join '; '))
}

if (-not `$InstallServicesPs1) {
    throw ('install_services.ps1 not found. Checked: ' + ((`$InstallServicesCandidates) -join '; '))
}

Write-Output ('[INFO] Suite root               : {0}' -f `$SuiteRoot)
Write-Output ('[INFO] Install-IndexerHost.ps1 : {0}' -f `$InstallIndexerHostPs1)
Write-Output ('[INFO] install_services.ps1    : {0}' -f `$InstallServicesPs1)

# ------------------------------------------------------------------
# Regenerate remote .env from env.json BEFORE validating secrets
# ------------------------------------------------------------------
`$SecretsRoot = 'C:\forensic_secrets'
`$EnvJsonPath = Join-Path `$SecretsRoot 'env.json'
`$EnvPath     = Join-Path `$SecretsRoot '.env'

if (-not (Test-Path `$SecretsRoot)) {
    throw '[CONFIG] Secrets root missing: C:\forensic_secrets'
}

if (-not (Test-Path `$EnvJsonPath)) {
    throw '[CONFIG] env.json missing: C:\forensic_secrets\env.json'
}

`$config = Get-Content `$EnvJsonPath -Raw | ConvertFrom-Json

`$envLines = @()

`$envLines += '# Postgres'
`$envLines += ('PGPASSWORD={0}' -f `$config.postgres.password)
`$envLines += ''

`$envLines += '# Ethereum'
`$envLines += ('QUICKNODE_ETH_HTTP={0}' -f `$config.eth.rpc_http)
`$envLines += ('QUICKNODE_ETH_WSS={0}' -f `$config.eth.rpc_wss)
`$envLines += ('QUICKNODE_ETH_ENDPOINT_1={0}' -f `$config.eth.rpc_url_1)
`$envLines += ('QUICKNODE_ETH_ENDPOINT_2={0}' -f `$config.eth.rpc_url_2)
`$envLines += ''

`$envLines += '# Tron'
`$envLines += ('QUICKNODE_TRON_ENDPOINT_1={0}' -f `$config.tron.grpc_endpoint)
`$envLines += ('QUICKNODE_TRON_ENDPOINT_2={0}' -f `$config.tron.fullnode_endpoint)
`$envLines += ''

`$envLines += '# Bitcoin'
`$envLines += ('QUICKNODE_BTC_ENDPOINT_1={0}' -f `$config.btc.rpc_url_1)
`$envLines += ('QUICKNODE_BTC_ENDPOINT_2={0}' -f `$config.btc.rpc_url_2)
`$envLines += ''

Set-Content -Path `$EnvPath -Value `$envLines -Encoding UTF8

Write-Output ('[INFO] Validating secrets at {0}' -f `$EnvPath)

`$lines = Get-Content `$EnvPath | Where-Object { `$_ -notmatch '^\s*#' -and `$_ -match '=' }

`$bad = @()
foreach (`$line in `$lines) {
    `$name, `$value = `$line.Split('=', 2)

    if (`$value -eq '' -or `$value -eq 'REPLACE_ME' -or `$value -like 'REPLACE_ME') {
        `$bad += `$name
    }
}

if (`$bad.Count -gt 0) {
    throw ('[CONFIG] Secrets contain placeholder values: {0}. Refusing to start services.' -f ((`$bad) -join ', '))
}

# ------------------------------------------------------------------
# Step 1: Run host bootstrap
# ------------------------------------------------------------------
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$InstallIndexerHostPs1
if (`$LASTEXITCODE -ne 0) {
    throw ('Install-IndexerHost.ps1 failed with exit code {0}' -f `$LASTEXITCODE)
}

# ------------------------------------------------------------------
# Step 2: Run service installer
# ------------------------------------------------------------------
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$InstallServicesPs1
if (`$LASTEXITCODE -ne 0) {
    throw ('install_services.ps1 failed with exit code {0}' -f `$LASTEXITCODE)
}

# ------------------------------------------------------------------
# Step 3: Ensure services are started
# ------------------------------------------------------------------
`$ServiceNames = @('btc_indexer', 'eth_indexer', 'tron_indexer', 'forensic_orchestrator')

foreach (`$svcName in `$ServiceNames) {
    `$svc = Get-Service -Name `$svcName -ErrorAction SilentlyContinue
    if (-not `$svc) {
        throw ('Required service missing after install: {0}' -f `$svcName)
    }

    if (`$svc.Status -ne 'Running') {
        Start-Service -Name `$svcName -ErrorAction Stop
    }
}

Start-Sleep -Seconds 5

# ------------------------------------------------------------------
# Step 4: Validate service health
# ------------------------------------------------------------------
`$svc = @(Get-Service -Name `$ServiceNames -ErrorAction SilentlyContinue)
`$badServices = @()

if (@(`$svc).Count -gt 0) {
    `$badServices = @(`$svc | Where-Object { `$_.Status -ne 'Running' })
}

if (@(`$badServices).Count -gt 0) {
    `$names = (@(`$badServices) | Select-Object -ExpandProperty Name) -join ', '
    throw ('Services not all running: {0}' -f `$names)
}

# ------------------------------------------------------------------
# Step 5: Validate wheel and state/log roots
# ------------------------------------------------------------------
`$WheelDir = Join-Path `$SuiteRoot 'wheel'
`$latestWheel = `$null
if (Test-Path `$WheelDir) {
    `$latestWheel = Get-ChildItem `$WheelDir -Filter 'forensic_suite_v2-*.whl' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if (-not `$latestWheel) {
    throw ('No forensic_suite_v2 wheel found in: {0}' -f `$WheelDir)
}

if (-not (Test-Path 'C:\forensic_suite_logs')) {
    throw 'Logs root missing: C:\forensic_suite_logs'
}

if (-not (Test-Path 'C:\forensic_state\btc')) {
    throw 'State directory missing: C:\forensic_state\btc'
}

if (-not (Test-Path 'C:\forensic_state\eth')) {
    throw 'State directory missing: C:\forensic_state\eth'
}

if (-not (Test-Path 'C:\forensic_state\tron')) {
    throw 'State directory missing: C:\forensic_state\tron'
}

# ------------------------------------------------------------------
# Step 6: Verify imports
# ------------------------------------------------------------------
& `$PythonExe -c "import orjson, yaml, prometheus_client; print('RUNTIME_OK')"
if (`$LASTEXITCODE -ne 0) {
    throw 'Core runtime dependency verification failed'
}

& `$PythonExe -c "import PySide6, qt_material, qasync, pyqtgraph, PIL; print('GUI_OK')"
if (`$LASTEXITCODE -ne 0) {
    throw 'GUI dependency verification failed'
}

& `$PythonExe -c "import forensic_suite_v2.gui.app; print('APP_IMPORT_OK')"
if (`$LASTEXITCODE -ne 0) {
    throw 'forensic_suite_v2.gui.app import verification failed'
}

Write-Output '[OK] Runtime prepared and services running.'
"@

    $result = Invoke-RemotePS -Host $Host -Script $script

    if ($result -eq "SSH_ERROR") {
        Write-Host "[FAIL] SSH execution failed on $Host" -ForegroundColor Red
        return 1
    }

    Write-Host "[DEBUG] Remote runtime output captured." -ForegroundColor DarkGray
    $text = ($result | Out-String)

    if ($text) {
        Write-Host $text.Trim()
    }

    if ($text -match '\[OK\] Runtime prepared and services running') {
        return 0
    }

    Write-Host "[FAIL] Runtime preparation did not report success on $Host" -ForegroundColor Red
    return 2
}

# ---------------------------------------------------------------------
# Validate environment
# ---------------------------------------------------------------------

if (-not $ProjectRoot) {
    throw "ProjectRoot is empty. Ensure `$Global:PrimaryRoot is set or pass -ProjectRoot."
}

$requiredCommands = @(
    "Invoke-Preflight",
    "Invoke-BuildSuite",
    "Invoke-DeployPreflight",
    "Invoke-DeployHost",
    "Invoke-DeployCluster",
    "Get-StatusReport",
    "Update-InstallerPayload",
    "Clear-ForensicSuiteAll",
	"Invoke-RemotePS"
)

foreach ($cmd in $requiredCommands) {
    Assert-ModuleCommand -Name $cmd
}

$resolvedHosts = Resolve-ReleaseHosts -RequestedHosts $Hosts

$allClusterHosts = @($Global:ClusterIPs) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$resolvedHosts   = @($resolvedHosts) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$deployingFullCluster = $false
if (@($allClusterHosts).Count -gt 0 -and @($resolvedHosts).Count -eq @($allClusterHosts).Count) {
    $requestedJoined = (@($resolvedHosts) | Sort-Object) -join ','
    $clusterJoined   = (@($allClusterHosts) | Sort-Object) -join ','
    $deployingFullCluster = ($requestedJoined -eq $clusterJoined)
}

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$deploymentStarted = $false
$deployedHosts = New-Object System.Collections.Generic.List[string]

Write-Stage "Forensic Suite Release Orchestration"
Write-Host "ProjectRoot              : $ProjectRoot" -ForegroundColor Gray
Write-Host "BuildOnly                : $BuildOnly" -ForegroundColor Gray
Write-Host "DeployOnly               : $DeployOnly" -ForegroundColor Gray
Write-Host "SkipClean                : $SkipClean" -ForegroundColor Gray
Write-Host "SkipPayloadRefresh       : $SkipPayloadRefresh" -ForegroundColor Gray
Write-Host "SkipStatusReport         : $SkipStatusReport" -ForegroundColor Gray
Write-Host "SkipPostBuildValidation  : $SkipPostBuildValidation" -ForegroundColor Gray
Write-Host "BlueGreen                : $BlueGreen" -ForegroundColor Gray
Write-Host "EnableRollback           : $EnableRollback" -ForegroundColor Gray
Write-Host "Hosts                    : $($resolvedHosts -join ', ')" -ForegroundColor Gray

try {
    # -------------------------------------------------------------
    # Build path
    # -------------------------------------------------------------
    if (-not $DeployOnly) {

        Write-Stage "Phase 1/6 - Preflight"
        $pre = Invoke-Preflight
        if ($pre -ne 0) {
            Write-Abort "Preflight failed with code $pre."
            return $pre
        }
        Write-Ok "Preflight passed."

        if (-not $SkipClean) {
            Write-Stage "Phase 2/6 - Clean runtime mirror"
            $clean = Clear-ForensicSuiteAll
            if ($clean -ne 0) {
                Write-Abort "Cleanup failed with code $clean."
                return $clean
            }
            Write-Ok "Runtime mirror cleaned."
        }
        else {
            Write-Warn "Skipping runtime mirror cleanup."
        }

        Write-Stage "Phase 3/6 - Build suite"
        $build = Invoke-BuildSuite
        if ($build -ne 0) {
            Write-Abort "Build suite failed with code $build."
            return $build
        }
        Write-Ok "Build suite completed."

        if (-not $SkipPayloadRefresh) {
            Write-Stage "Phase 4/6 - Refresh installer payload"
            $payload = Update-InstallerPayload
            if ($payload -ne 0) {
                Write-Abort "Payload refresh failed with code $payload."
                return $payload
            }
            Write-Ok "Installer payload refreshed."
        }
        else {
            Write-Warn "Skipping explicit payload refresh."
        }

        if (-not $SkipPostBuildValidation) {
            Write-Stage "Phase 5/6 - Deploy preflight"
            $deployPre = Invoke-DeployPreflight
            if ($deployPre -ne 0) {
                Write-Abort "Deploy preflight failed with code $deployPre."
                return $deployPre
            }
            Write-Ok "Deploy preflight passed."
        }
        else {
            Write-Warn "Skipping deploy preflight."
        }

        if ($BuildOnly) {
            $timer.Stop()
            Write-Stage "Release Result"
            Write-Host "Mode         : BUILD ONLY" -ForegroundColor Yellow
            Write-Host "Elapsed      : $($timer.Elapsed.ToString())" -ForegroundColor Yellow
            return 0
        }
    }
    else {
        Write-Stage "Phase 1/2 - Deploy preflight"
        $deployPre = Invoke-DeployPreflight
        if ($deployPre -ne 0) {
            Write-Abort "Deploy preflight failed with code $deployPre."
            return $deployPre
        }
        Write-Ok "Deploy preflight passed."
    }

    # -------------------------------------------------------------
    # Deploy path
    # -------------------------------------------------------------
    Write-Stage "Phase 6/6 - Deploy"

    if ($deployingFullCluster) {
		$deploymentStarted = $true

		try {
			$script:LASTEXITCODE = 0
			$deployOutput = Invoke-DeployCluster -BlueGreen:$BlueGreen 2>&1

			if ($deployOutput) {
				$deployOutput | ForEach-Object { Write-Host $_ }
			}

			if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
				if ($EnableRollback) {
					Invoke-ReleaseRollback -RollbackHosts $resolvedHosts -RollbackBlueGreen:$BlueGreen
				}

				Write-Abort "Cluster deployment failed with exit code $LASTEXITCODE."
				return $LASTEXITCODE
			}

			foreach ($host in $resolvedHosts) {
				$prep = Invoke-RemoteRuntimePrepare -Host $host
				if ($prep -ne 0) {
					if ($EnableRollback) {
						Invoke-ReleaseRollback -RollbackHosts $resolvedHosts -RollbackBlueGreen:$BlueGreen
					}

					Write-Abort "Runtime preparation failed for $host after cluster deployment."
					return $prep
				}

				[void]$deployedHosts.Add($host)
			}

			Write-Ok "Cluster deployment completed."
		}
		catch {
			if ($EnableRollback) {
				Invoke-ReleaseRollback -RollbackHosts $resolvedHosts -RollbackBlueGreen:$BlueGreen
			}

			Write-Abort "Cluster deployment failed: $($_.Exception.Message)"
			return 500
		}
	}
    else {
		foreach ($host in $resolvedHosts) {
			Write-Info "Deploying host $host ..."
			$deploymentStarted = $true

			try {
				$script:LASTEXITCODE = 0
				$deployOutput = Invoke-DeployHost -IP $host -BlueGreen:$BlueGreen 2>&1

				if ($deployOutput) {
					$deployOutput | ForEach-Object { Write-Host $_ }
				}

				if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
					if ($EnableRollback -and @($deployedHosts).Count -gt 0) {
						Invoke-ReleaseRollback -RollbackHosts $deployedHosts.ToArray() -RollbackBlueGreen:$BlueGreen
					}

					Write-Abort "Deployment failed for $host with exit code $LASTEXITCODE."
					return $LASTEXITCODE
				}

				$prep = Invoke-RemoteRuntimePrepare -Host $host
				if ($prep -ne 0) {
					if ($EnableRollback -and @($deployedHosts).Count -gt 0) {
						Invoke-ReleaseRollback -RollbackHosts $deployedHosts.ToArray() -RollbackBlueGreen:$BlueGreen
					}

					Write-Abort "Runtime preparation failed for $host."
					return $prep
				}

				[void]$deployedHosts.Add($host)
				Write-Ok "Deployment completed for $host."
			}
			catch {
				if ($EnableRollback -and @($deployedHosts).Count -gt 0) {
					Invoke-ReleaseRollback -RollbackHosts $deployedHosts.ToArray() -RollbackBlueGreen:$BlueGreen
				}

				Write-Abort "Deployment failed for ${host}: $($_.Exception.Message)"
				return 500
			}
		}
	}
    if (-not $SkipStatusReport) {
        Write-Stage "Final Cluster Status"
        Get-StatusReport
    }
    else {
        Write-Warn "Skipping final status report."
    }

    $timer.Stop()

    Write-Stage "Release Result"
    Write-Host "Mode         : COMPLETE" -ForegroundColor Green
    Write-Host "Elapsed      : $($timer.Elapsed.ToString())" -ForegroundColor Green
    Write-Host "Hosts        : $($resolvedHosts -join ', ')" -ForegroundColor Green

    return 0
}
catch {
    $timer.Stop()

    if ($EnableRollback -and $deploymentStarted -and @($deployedHosts).Count -gt 0) {
        Invoke-ReleaseRollback -RollbackHosts $deployedHosts.ToArray() -RollbackBlueGreen:$BlueGreen
    }

    Write-Abort "Unhandled exception: $($_.Exception.Message)"
    return 999
}




