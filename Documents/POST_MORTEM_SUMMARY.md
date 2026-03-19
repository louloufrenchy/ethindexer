Post‑mortem summary
Incident:  
Automated deployment to 192.168.0.172 reported success, but no services (btc_indexer, eth_indexer, tron_indexer, forensic_orchestrator) were installed or running; no logs existed under C:\forensic_suite_logs.

Impact:

.172 was reported as deployed but was not operational.

Cluster status showed MISSING for all services and WHEEL: NONE.

Risk of false‑positive “healthy” deployments across the fleet.

Root cause:

In the remote runtime‑prep script (Invoke-RemoteRuntimePrepare), the wheel install block referenced $latestWheel.FullName under StrictMode without guaranteeing $latestWheel was initialized.

When $latestWheel was not set, StrictMode raised:

“The variable '$latestWheel' cannot be retrieved because it has not been set.”

This exception occurred before the install_services.ps1 call, causing the remote script to exit early.

The deploy pipeline did not surface this failure clearly, so the deployment was treated as successful while services were never installed.

Contributing factors:

StrictMode on the remote host.

Assumption that $latestWheel would always be assigned.

Error message from the remote script was not clearly propagated or interpreted as a hard failure.

Resolution:

Hardened the wheel block in Invoke-RemoteRuntimePrepare to be StrictMode‑safe:

Explicitly initialize $latestWheel = $null.

Guard the “no wheel found” case with a clear throw.

Use -f formatting instead of $($latestWheel.FullName) interpolation.

Refreshed installer payload and redeployed.

Verified that runtime‑prep now runs to completion and install_services.ps1 executes, resulting in all services installed and running.

Lessons learned:

Remote scripts must be StrictMode‑safe, especially around optional variables.

Any failure in runtime‑prep must be surfaced as a hard failure to the orchestrator.

Service presence and logs are critical post‑deploy validation signals and should be part of automated healthchecks.

Permanent regression test for this failure mode
Goal: Ensure future changes cannot reintroduce the “$latestWheel not set / services not installed” failure.

Test concept: A scripted, repeatable test that:

Deploys to a test host with StrictMode enabled.

Forces a scenario where the wheel is present and where it is absent.

Verifies:

Runtime‑prep fails with a clear “No wheel found” error when wheel is absent.

Runtime‑prep succeeds and services are installed when wheel is present.

Services and logs exist after a successful run.

Pseudo‑test (PowerShell):

powershell
# Precondition: test host, StrictMode enabled, clean slots

$host = "192.168.0.172"

# Case 1: No wheel → must fail clearly
ssh forensicuser@$host "powershell -Command Remove-Item -Recurse -Force C:\forensic_suite_v2\wheel -ErrorAction SilentlyContinue"
$exit = Invoke-RemoteRuntimePrepare -Host $host
if ($exit -eq 0) {
    throw "REGRESSION: Runtime prep succeeded with no wheel present."
}

# Case 2: Wheel present → must succeed and install services
# (Re-deploy or copy wheel back into C:\forensic_suite_v2\wheel first)
$exit = Invoke-RemoteRuntimePrepare -Host $host
if ($exit -ne 0) {
    throw "REGRESSION: Runtime prep failed with wheel present."
}

$svc = ssh forensicuser@$host "powershell -Command Get-Service btc_indexer,eth_indexer,tron_indexer,forensic_orchestrator"
if (-not $svc) {
    throw "REGRESSION: Services not installed after successful runtime prep."
}
You can formalize this into a dedicated Test-RuntimePrep.ps1 and run it as part of your pre‑release validation.

Runtime‑prep healthcheck script
Goal: Quickly validate that a host’s runtime is correctly prepared and services are installed and running.

powershell
param(
    [Parameter(Mandatory = $true)][string]$Host
)

Write-Host "=== Runtime Prep Healthcheck for $Host ===" -ForegroundColor Cyan

$script = @"
`$ErrorActionPreference = 'Stop'

`$PythonExe = 'C:\Program Files\Python314\python.exe'
`$SuiteRoot = 'C:\forensic_suite_v2'
`$WheelDir  = Join-Path `$SuiteRoot 'wheel'
`$LogsRoot  = 'C:\forensic_suite_logs'

Write-Host "[INFO] Checking Python..." -ForegroundColor Gray
if (-not (Test-Path `$PythonExe)) { throw "Python missing: `$PythonExe" }

Write-Host "[INFO] Checking suite root..." -ForegroundColor Gray
if (-not (Test-Path `$SuiteRoot)) { throw "Suite root missing: `$SuiteRoot" }

Write-Host "[INFO] Checking wheel directory..." -ForegroundColor Gray
if (-not (Test-Path `$WheelDir)) { throw "Wheel directory missing: `$WheelDir" }

`$wheel = Get-ChildItem `$WheelDir -Filter 'forensic_suite_v2-*.whl' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not `$wheel) { throw "No forensic_suite_v2 wheel found in `$WheelDir" }

Write-Host "[OK] Wheel: $(`$wheel.FullName)" -ForegroundColor Green

Write-Host "[INFO] Checking services..." -ForegroundColor Gray
`$svc = Get-Service btc_indexer,eth_indexer,tron_indexer,forensic_orchestrator -ErrorAction SilentlyContinue

if (-not `$svc -or `$svc.Count -lt 4) {
    throw "One or more services are missing."
}

`$bad = `$svc | Where-Object { `$_.Status -ne 'Running' }
if (`$bad) {
    `$names = (`$bad | Select-Object -ExpandProperty Name) -join ', '
    throw "Services not running: `$names"
}

Write-Host "[OK] All services running." -ForegroundColor Green

Write-Host "[INFO] Checking logs root..." -ForegroundColor Gray
if (-not (Test-Path `$LogsRoot)) { throw "Logs root missing: `$LogsRoot" }

Write-Host "[OK] Runtime prep healthcheck passed." -ForegroundColor Green
"@

$result = Invoke-RemotePS -Host $Host -Script $script
$result
You can wrap this as Test-ForensicRuntime.ps1 and call it per host or cluster‑wide.

Cluster‑wide redeploy plan
Objective: Bring all hosts to the same deterministic, known‑good state as 192.168.0.172.

Assumptions:

Invoke-RemoteRuntimePrepare is patched and payload refreshed.

Control host has the latest code and payload.

Global:ClusterIPs contains all target hosts.

Plan:

Pre‑flight (control host):

Build:

powershell
Invoke-Preflight
Clear-ForensicSuiteAll
Invoke-BuildSuite
Update-InstallerPayload
Invoke-DeployPreflight

Confirm no errors.

Target selection:

Start with one “canary” host (you already used .172).

Then roll out to the rest: .199, .165, .28, etc.

Cluster deploy (control host):

For full cluster:

powershell
Invoke-ForensicRelease -BlueGreen -EnableRollback
For a subset:

powershell
Invoke-ForensicRelease -BlueGreen -EnableRollback -Hosts 192.168.0.199,192.168.0.165,192.168.0.28
Post‑deploy healthcheck (per host):

Run the runtime‑prep healthcheck:

powershell
.\Test-ForensicRuntime.ps1 -Host 192.168.0.199
.\Test-ForensicRuntime.ps1 -Host 192.168.0.165
.\Test-ForensicRuntime.ps1 -Host 192.168.0.28
Confirm:

Python present

Suite root present

Wheel present

All four services installed and Running

Logs root exists

Cluster status verification:

Run your existing status command (e.g., Get-StatusReport / Compare-StatusReport.ps1) and confirm:

SLOT is consistent (BLUE or GREEN as expected).

BTC/ETH/TRON/ORCH are Running or Stopped (not MISSING).

WHEEL is not NONE for active slots.

Rollback strategy (already wired):

If any host fails runtime‑prep or service install:

Invoke-ForensicRelease with -EnableRollback will flip the symlink back to the previous slot for that host.

You can also explicitly call your rollback orchestration if needed.

🧠 Do all services need to be running for ingestion?
✔ YES — ingestion requires all three indexers
✔ The orchestrator alone is not enough
Here’s the ingestion model:

Component				Required for ingestion?			Why
btc_indexer				✔ Required						Scans BTC blocks, writes state
eth_indexer				✔ Required						Scans ETH blocks, writes state
tron_indexer			✔ Required						Scans TRON blocks, writes state
forensic_orchestrator	✔ Required						Supervises indexers, performs health checks

If only the orchestrator is running:
It will start up

It will check for indexers

It will find none

It will log failures

No ingestion will occur

The orchestrator is a supervisor, not an indexer.

Healthy ingestion requires:
All three indexers Running

Orchestrator Running

Logs being written to:

C:\forensic_suite_logs\btc_indexer.out.log
C:\forensic_suite_logs\eth_indexer.out.log
C:\forensic_suite_logs\tron_indexer.out.log

🔍 How to confirm ingestion is actually happening
You can confirm ingestion activity in three ways:

1. Tail the indexer logs
Code
Get-Content C:\forensic_suite_logs\btc_indexer.out.log -Tail 50
Get-Content C:\forensic_suite_logs\eth_indexer.out.log -Tail 50
Get-Content C:\forensic_suite_logs\tron_indexer.out.log -Tail 50
You should see:

Block heights increasing

“Processed block …”

“Wrote batch …”

2. Check the state directories
Code
dir C:\forensic_state\btc
dir C:\forensic_state\eth
dir C:\forensic_state\tron
You should see:

checkpoint files

state files

cache files

3. Query the orchestrator health endpoint (if enabled)
If your orchestrator exposes a health port, you can hit it to confirm ingestion status.

🧩 Why ingestion wasn’t happening before
Because:

The automated deploy never installed services

So:

No indexers existed

No orchestrator existed

No logs existed

No ingestion occurred

Once you manually ran install_services.ps1, ingestion became possible.

🟩 Summary
Where to keep the tests:
Code
scripts\validation\Test-RuntimePrep.ps1
scripts\validation\Test-ForensicRuntime.ps1
Do all services need to run?
Yes.  
The orchestrator alone cannot ingest anything.

How to confirm ingestion?
Tail indexer logs

Inspect state directories

Check orchestrator health

Service dependency diagram specifically for ingestion
text
                    ┌────────────────────────────┐
                    │   forensic_orchestrator    │
                    │   (supervisor / coordinator│
                    └─────────────┬──────────────┘
                                  │
          ┌───────────────────────┼────────────────────────┐
          ▼                       ▼                        ▼
┌──────────────────┐   ┌──────────────────┐     ┌──────────────────┐
│   btc_indexer     │   │   eth_indexer    │     │  tron_indexer     │
│   (BTC ingestion) │   │   (ETH ingestion)│     │  (TRON ingestion) │
└─────────┬─────────┘   └─────────┬────────┘     └─────────┬────────┘
          │                       │                        │
          ▼                       ▼                        ▼
┌──────────────────┐   ┌──────────────────┐     ┌──────────────────┐
│  BTC node / API   │   │  ETH node / API  │     │  TRON node / API  │
└──────────────────┘   └──────────────────┘     └──────────────────┘

All depend on:
- C:\Program Files\Python314\python.exe
- forensic_suite_v2 package
- C:\forensic_state\{btc,eth,tron}
- C:\forensic_suite_logs
- env.json / config
“What healthy ingestion looks like” checklist
All services present and running:

powershell
Get-Service btc_indexer,eth_indexer,tron_indexer,forensic_orchestrator
Expect: all Status = Running.

Logs directory populated:

powershell
Get-ChildItem C:\forensic_suite_logs
Expect: btc_indexer.out.log, eth_indexer.out.log, tron_indexer.out.log, plus .err.log companions.

Indexers show forward progress:

Tail logs:

powershell
Get-Content C:\forensic_suite_logs\btc_indexer.out.log -Tail 50
Get-Content C:\forensic_suite_logs\eth_indexer.out.log -Tail 50
Get-Content C:\forensic_suite_logs\tron_indexer.out.log -Tail 50
Expect: messages like “processed block …”, “wrote batch …”, heights increasing.

State directories are non‑empty:

powershell
dir C:\forensic_state\btc
dir C:\forensic_state\eth
dir C:\forensic_state\tron
Expect: checkpoint/state files present and updating over time.

No persistent errors in .err.log:

powershell
Get-Content C:\forensic_suite_logs\btc_indexer.err.log -Tail 50
Get-Content C:\forensic_suite_logs\eth_indexer.err.log -Tail 50
Get-Content C:\forensic_suite_logs\tron_indexer.err.log -Tail 50
Expect: either empty or transient warnings, no repeated fatal errors.

Orchestrator supervising correctly:

powershell
Get-Content C:\forensic_suite_logs\forensic_orchestrator.out.log -Tail 50
Expect: periodic health checks, restarts if needed, no “indexer missing” loops.

Log‑based ingestion validator (block height movement across all chains)
Drop this on the control host as e.g. scripts\validation\Test-IngestionProgress.ps1:

Interpretation:

For each chain (btc, eth, tron) you get:

Before: last seen height at T0

After: last seen height at T0 + WaitSeconds

Delta: After - Before

Healthy ingestion: Delta > 0 for all chains (or at least for those you expect active).

Stalled ingestion: Delta = 0 or null → indexer not progressing or logs not being written.

You can run this per host:

powershell
.\scripts\validation\Test-IngestionProgress.ps1 -TargetHost 192.168.0.172 -WaitSeconds 60

🧠 What this script gives you
✔ Deterministic ingestion validation
It checks:

BTC height movement

ETH height movement

TRON height movement

✔ Strong regex
It supports all your indexer log formats:

height=12345

block_height: 12345

"height": 12345

✔ Clean output
You get:

Chain	Before	After	Delta
BTC		12345	12360	15
ETH		98765	98780	15
TRON	54321	54340	19
✔ Clear failure modes
If logs are missing, heights don’t move, or Invoke‑RemotePS fails, you get a precise error.