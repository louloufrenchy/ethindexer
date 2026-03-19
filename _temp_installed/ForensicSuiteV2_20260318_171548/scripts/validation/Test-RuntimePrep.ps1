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
