function Invoke-Rollback {
    param(
        [array]$Hosts,
        [array]$Steps
    )

    foreach ($TargetHost in $Hosts) {

        Write-Host "Starting rollback on $($TargetHost.Address)..."

        foreach ($step in $Steps | Sort-Object Id -Descending) {

            # Skip steps with no rollback defined
            if (-not $step.Rollback) { continue }

            # Skip rollback if the step never succeeded
            if ($step.Type -eq 'SCP' -and -not (Test-Path $step.Artifact)) {
                Write-Host "Skipping rollback for $($step.Id) on $($TargetHost.Address) (artifact never uploaded)"
                continue
            }

            switch ($step.Rollback.Type) {

                'DeleteFile' {
                    $remote = $step.Rollback.Path
                    $cmd = "powershell -NoProfile -Command `"if (Test-Path '$remote') { Remove-Item -Force '$remote' }`""

                    Invoke-SSH -TargetHost $TargetHost.Address -Command $cmd
                }

                'SSH' {
                    # Ensure remote command is quoted correctly
                    $cmd = $step.Rollback.Command
                    Invoke-SSH -TargetHost $TargetHost.Address -Command $cmd
                }
            }
        }
    }
}
