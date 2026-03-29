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

`$SuiteRootCandidates = @(
    'C:\forensic_suite_v2',
    'C:\forensic_suite_v2_blue',
    'C:\forensic_suite_v2_green'
)

`$SuiteRoot = Resolve-FirstExistingPath -Candidates `$SuiteRootCandidates
if (-not `$SuiteRoot) {
    throw 'No suite root found under C:\forensic_suite_v2, C:\forensic_suite_v2_blue, or C:\forensic_suite_v2_green'
}

`$PythonExeCandidates = @(
    (Join-Path `$SuiteRoot 'python\python.exe'),
    'C:\forensic_suite_v2\python\python.exe',
    'C:\forensic_suite_v2_blue\python\python.exe',
    'C:\forensic_suite_v2_green\python\python.exe'
)

`$PythonExe = Resolve-FirstExistingPath -Candidates `$PythonExeCandidates
if (-not `$PythonExe) {
    throw ('No slot-local Python runtime found. Checked: {0}' -f ((`$PythonExeCandidates) -join '; '))
}

Write-Output ('[INFO] Suite root            : {0}' -f `$SuiteRoot)
Write-Output ('[INFO] Python runtime        : {0}' -f `$PythonExe)

New-Item -ItemType Directory -Path 'C:\forensic_state' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\forensic_state\btc' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\forensic_state\eth' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\forensic_state\tron' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\forensic_suite_logs' -Force | Out-Null

`$ToggleScriptCandidates = @(
    (Join-Path $SuiteRoot 'scripts\maintenance\Set-HostChainMode.ps1'),  # authoritative
    (Join-Path $SuiteRoot 'scripts\Set-HostChainMode.ps1'),              # fallback (older builds)
    (Join-Path $SuiteRoot 'forensic_suite_v2\scripts\Set-HostChainMode.ps1') # legacy fallback
)

`$ToggleScript = Resolve-FirstExistingPath -Candidates `$ToggleScriptCandidates
if (-not `$ToggleScript) {
    throw ('Set-HostChainMode.ps1 not found. Checked: ' + ((`$ToggleScriptCandidates) -join '; '))
}

Write-Output ('[INFO] Chain toggle script   : {0}' -f `$ToggleScript)

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
    if (`$value -eq '' -or `$value -eq 'REPLACE_ME' -or `$value -like '*REPLACE_ME*') {
        `$bad += `$name
    }
}
if (`$bad.Count -gt 0) {
    throw ('[CONFIG] Secrets contain placeholder values: {0}. Refusing to start services.' -f ((`$bad) -join ', '))
}

Write-Output '[STEP] Applying host-specific chain configuration...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$ToggleScript
if (`$LASTEXITCODE -ne 0) {
    throw ('Set-HostChainMode.ps1 failed with exit code {0}' -f `$LASTEXITCODE)
}
Write-Output '[INFO] Chain toggle step completed.'

`$InstallServicesPyCandidates = @(
    (Join-Path `$SuiteRoot 'forensic_suite_v2\scripts\install_services.py'),
    'C:\forensic_suite_v2\forensic_suite_v2\scripts\install_services.py',
    'C:\forensic_suite_v2_blue\forensic_suite_v2\scripts\install_services.py',
    'C:\forensic_suite_v2_green\forensic_suite_v2\scripts\install_services.py'
)

`$InstallServicesPs1Candidates = @(
    (Join-Path `$SuiteRoot 'forensic_suite_v2\scripts\install_services.ps1'),
    'C:\forensic_suite_v2\forensic_suite_v2\scripts\install_services.ps1',
    'C:\forensic_suite_v2_blue\forensic_suite_v2\scripts\install_services.ps1',
    'C:\forensic_suite_v2_green\forensic_suite_v2\scripts\install_services.ps1'
)

`$InstallServicesPy  = Resolve-FirstExistingPath -Candidates `$InstallServicesPyCandidates
`$InstallServicesPs1 = Resolve-FirstExistingPath -Candidates `$InstallServicesPs1Candidates

if (`$InstallServicesPy) {
    Write-Output ('[INFO] install_services.py   : {0}' -f `$InstallServicesPy)
    & `$PythonExe `$InstallServicesPy
    if (`$LASTEXITCODE -ne 0) {
        throw ('install_services.py failed with exit code {0}' -f `$LASTEXITCODE)
    }
}
elseif (`$InstallServicesPs1) {
    Write-Output ('[INFO] install_services.ps1  : {0}' -f `$InstallServicesPs1)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$InstallServicesPs1
    if (`$LASTEXITCODE -ne 0) {
        throw ('install_services.ps1 failed with exit code {0}' -f `$LASTEXITCODE)
    }
}
else {
    `$checked = ((`$InstallServicesPyCandidates + `$InstallServicesPs1Candidates) -join '; ')
    throw ('No install_services installer found. Checked: {0}' -f `$checked)
}

Start-Sleep -Seconds 8

`$ConfigPath = Join-Path `$SuiteRoot 'forensic_suite_v2\config\indexer.yaml'
if (-not (Test-Path `$ConfigPath)) {
    throw ('Config file not found after install: {0}' -f `$ConfigPath)
}

`$rawYaml = Get-Content `$ConfigPath -Raw
`$expected = @('forensic_orchestrator')
if (`$rawYaml -match '(?ms)^btc:\r?\n.*?^\s*enabled:\s*true\s*$')  { `$expected += 'btc_indexer'  }
if (`$rawYaml -match '(?ms)^eth:\r?\n.*?^\s*enabled:\s*true\s*$')  { `$expected += 'eth_indexer'  }
if (`$rawYaml -match '(?ms)^tron:\r?\n.*?^\s*enabled:\s*true\s*$') { `$expected += 'tron_indexer' }

Write-Output ('[INFO] Expected services      : {0}' -f ((`$expected) -join ', '))

`$svc = @(Get-Service -Name `$expected -ErrorAction SilentlyContinue)
if (@(`$svc).Count -eq 0) {
    throw 'No expected services were found after install.'
}

`$badServices = @(`$svc | Where-Object { `$_.Status -ne 'Running' -and `$_.Status -ne 'StartPending' -and `$_.Status -ne 'Paused' })
if (@(`$badServices).Count -gt 0) {
    `$names = (@(`$badServices) | Select-Object -ExpandProperty Name) -join ', '
    throw ('Services not all running: {0}' -f `$names)
}

if (`$rawYaml -match '(?ms)^eth:\r?\n.*?^\s*enabled:\s*true\s*$') {
    Write-Output '[STEP] Validating ETH runtime context...'
    & `$PythonExe -c "import forensic_suite_v2.eth_indexer.services.run_eth_indexer_v2 as m; cfg=m.load_config(); print('[ETH-CHECK] http=' + str(cfg['eth']['http_endpoint'])); print('[ETH-CHECK] wss=' + str(cfg['eth']['wss_endpoint']))"
    if (`$LASTEXITCODE -ne 0) {
        throw 'ETH runtime config validation failed'
    }
}

& `$PythonExe -c "import orjson, yaml, prometheus_client; print('RUNTIME_OK')"
if (`$LASTEXITCODE -ne 0) {
    throw 'Core runtime dependency verification failed'
}

Write-Output '[OK] Runtime prepared and services running.'
"@

    $result = Invoke-RemotePS -TargetHost $Host -Script $script

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
