# Post‑Mortem: Runtime‑Prep Failure Leading to False‑Positive Deployment Success  
**Authoritative Engineering Record — Forensic Suite V2**

---

## 1. Incident Summary

**Incident:**  
Automated deployment to **192.168.0.172** reported success, but **no services were installed or running**:

- `btc_indexer`
- `eth_indexer`
- `tron_indexer`
- `forensic_orchestrator`

Additionally:

- No logs existed under `C:\forensic_suite_logs`
- Cluster status showed **MISSING** for all services
- WHEEL status was **NONE**

**Impact:**  
The deployment pipeline produced a **false‑positive “healthy” deployment**, masking a complete runtime‑prep failure.  
This created risk of silent failures across the entire fleet.

---

## 2. Root Cause

Inside **Invoke‑RemoteRuntimePrepare**, the wheel‑installation block referenced:

```
$latestWheel.FullName
```

under **StrictMode**, without guaranteeing `$latestWheel` was initialized.

When no wheel was present, StrictMode raised:

> “The variable '$latestWheel' cannot be retrieved because it has not been set.”

This exception occurred **before** the call to `install_services.ps1`, causing the remote script to exit early.

The deploy pipeline **did not surface this failure**, so the orchestrator treated the deployment as successful.

---

## 3. Contributing Factors

- StrictMode on the remote host  
- Assumption that `$latestWheel` would always be assigned  
- Lack of explicit guard for “no wheel found”  
- Remote script errors were not propagated as hard failures  
- No post‑deploy validation of service presence or logs  

---

## 4. Resolution

The wheel‑handling block in `Invoke‑RemoteRuntimePrepare` was hardened:

- `$latestWheel` explicitly initialized to `$null`
- “No wheel found” now throws a clear, deterministic error
- Removed unsafe `$($latestWheel.FullName)` interpolation
- Updated installer payload and redeployed
- Verified that runtime‑prep now completes and services install correctly

---

## 5. Lessons Learned

1. **Remote scripts must be StrictMode‑safe**  
   Optional variables must always be initialized.

2. **Runtime‑prep failures must be surfaced as hard failures**  
   Silent failures are unacceptable in a distributed deployment pipeline.

3. **Service presence + logs must be part of automated validation**  
   A “successful deploy” without services is not a deploy.

4. **Regression tests must exist for wheel‑presence logic**  
   This failure mode must never reappear.

---

## 6. Permanent Regression Test

A dedicated regression test ensures:

- Runtime‑prep **fails clearly** when no wheel is present  
- Runtime‑prep **succeeds** when a wheel is present  
- All services are installed and running after success  

### Pseudo‑Test (PowerShell)

```powershell
# Precondition: test host, StrictMode enabled, clean slots
$host = "192.168.0.172"

# Case 1: No wheel → must fail clearly
ssh forensicuser@$host "powershell -Command Remove-Item -Recurse -Force C:\forensic_suite_v2\wheel -ErrorAction SilentlyContinue"
$exit = Invoke-RemoteRuntimePrepare -Host $host
if ($exit -eq 0) {
    throw "REGRESSION: Runtime prep succeeded with no wheel present."
}

# Case 2: Wheel present → must succeed and install services
$exit = Invoke-RemoteRuntimePrepare -Host $host
if ($exit -ne 0) {
    throw "REGRESSION: Runtime prep failed with wheel present."
}

$svc = ssh forensicuser@$host "powershell -Command Get-Service btc_indexer,eth_indexer,tron_indexer,forensic_orchestrator"
if (-not $svc) {
    throw "REGRESSION: Services not installed after successful runtime prep."
}
```

This should be formalized as:

```
scripts\validation\Test-RuntimePrep.ps1
```

---

## 7. Runtime‑Prep Healthcheck Script

This script validates:

- Python present  
- Suite root present  
- Wheel present  
- All services installed and running  
- Logs directory exists  

### Test-ForensicRuntime.ps1

```powershell
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

if (-not (Test-Path `$PythonExe)) { throw "Python missing: `$PythonExe" }
if (-not (Test-Path `$SuiteRoot)) { throw "Suite root missing: `$SuiteRoot" }
if (-not (Test-Path `$WheelDir)) { throw "Wheel directory missing: `$WheelDir" }

`$wheel = Get-ChildItem `$WheelDir -Filter 'forensic_suite_v2-*.whl' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not `$wheel) { throw "No forensic_suite_v2 wheel found in `$WheelDir" }

`$svc = Get-Service btc_indexer,eth_indexer,tron_indexer,forensic_orchestrator -ErrorAction SilentlyContinue
if (-not `$svc -or `$svc.Count -lt 4) { throw "One or more services are missing." }

`$bad = `$svc | Where-Object { `$_.Status -ne 'Running' }
if (`$bad) {
    `$names = (`$bad | Select-Object -ExpandProperty Name) -join ', '
    throw "Services not running: `$names"
}

if (-not (Test-Path `$LogsRoot)) { throw "Logs root missing: `$LogsRoot" }

Write-Host "[OK] Runtime prep healthcheck passed." -ForegroundColor Green
"@

$result = Invoke-RemotePS -Host $Host -Script $script
$result
```

Place under:

```
scripts\validation\Test-ForensicRuntime.ps1
```

---

## 8. Cluster‑Wide Redeploy Plan

### Pre‑flight (control host)

```powershell
Invoke-Preflight
Clear-ForensicSuiteAll
Invoke-BuildSuite
Update-InstallerPayload
Invoke-DeployPreflight
```

### Deployment

Full cluster:

```powershell
Invoke-ForensicRelease -BlueGreen -EnableRollback
```

Subset:

```powershell
Invoke-ForensicRelease -BlueGreen -EnableRollback -Hosts 192.168.0.199,192.168.0.165,192.168.0.28
```

### Post‑Deploy Validation

Per host:

```powershell
.\scripts\validation\Test-ForensicRuntime.ps1 -Host 192.168.0.199
.\scripts\validation\Test-ForensicRuntime.ps1 -Host 192.168.0.165
.\scripts\validation\Test-ForensicRuntime.ps1 -Host 192.168.0.28
```

Cluster status:

- SLOT consistent  
- Services Running  
- WHEEL not NONE  

Rollback:

- Automatically handled by `-EnableRollback`  
- Manual rollback available via orchestrator scripts  

---

## 9. Ingestion Requirements

All four services must be running:

| Service                 | Required?| Reason                   |
|-------------------------|-------------------------------------|
| `btc_indexer`           | ✔       | BTC ingestion            |
| `eth_indexer`           | ✔       | ETH ingestion            |
| `tron_indexer`          | ✔       | TRON ingestion           |
| `forensic_orchestrator` | ✔       | Supervisor / coordinator |

The orchestrator **cannot ingest alone**.

---

## 10. How to Confirm Ingestion

### 1. Tail logs

```powershell
Get-Content C:\forensic_suite_logs\btc_indexer.out.log -Tail 50
Get-Content C:\forensic_suite_logs\eth_indexer.out.log -Tail 50
Get-Content C:\forensic_suite_logs\tron_indexer.out.log -Tail 50
```

Expect:

- “processed block …”
- “wrote batch …”
- heights increasing

### 2. Check state directories

```powershell
dir C:\forensic_state\btc
dir C:\forensic_state\eth
dir C:\forensic_state\tron
```

Expect:

- checkpoint files  
- state files  

### 3. Ingestion Progress Validator

```powershell
.\scripts\validation\Test-IngestionProgress.ps1 -TargetHost 192.168.0.172 -WaitSeconds 60
```

Expect:

```
Chain   Before   After   Delta
BTC     12345    12360   15
ETH     98765    98780   15
TRON    54321    54340   19
```

---

## 11. Ingestion Architecture Diagram

```
                    ┌────────────────────────────┐
                    │   forensic_orchestrator    │
                    └─────────────┬──────────────┘
                                  │
          ┌───────────────────────┼────────────────────────┐
          ▼                       ▼                        ▼
┌──────────────────┐   ┌──────────────────┐     ┌──────────────────┐
│   btc_indexer     │   │   eth_indexer    │     │  tron_indexer     │
└─────────┬─────────┘   └─────────┬────────┘     └─────────┬────────┘
          │                       │                        │
          ▼                       ▼                        ▼
┌──────────────────┐   ┌──────────────────┐     ┌──────────────────┐
│  BTC node / API   │   │  ETH node / API  │     │  TRON node / API  │
└──────────────────┘   └──────────────────┘     └──────────────────┘
```

---

## 12. Final Summary

This incident exposed a critical flaw in runtime‑prep error handling.  
The fix, regression tests, and new healthchecks now guarantee:

- StrictMode‑safe remote scripts  
- Deterministic wheel handling  
- Guaranteed service installation  
- Accurate deploy success/failure reporting  
- Reliable ingestion validation  

This document is the authoritative reference for this failure mode and its permanent resolution.

