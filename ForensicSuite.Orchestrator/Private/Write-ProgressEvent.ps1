function Write-ProgressEvent {
    param(
        [string]$Phase,
        [string]$StepId,
        [string]$HostName,
        [string]$Status,
        [string]$Detail
    )

    # Ensure log directory exists
    $logDir = ".\logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    $event = [pscustomobject]@{
        Time    = Get-Date
        Phase   = $Phase
        StepId  = $StepId
        TargetHost = $HostName
        Status  = $Status
        Detail  = $Detail
    }

    # Atomic append, avoids partial writes under parallel load
    $event | ConvertTo-Json -Depth 5 | Out-File -FilePath "$logDir\orchestrator.log.json" -Append -Encoding utf8

    # Console output
    Write-Host ("[{0}] {1} | {2} | {3} | {4}" -f $event.Time, $Phase, $StepId, $HostName, $Status)
}
