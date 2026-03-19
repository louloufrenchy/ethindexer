function Invoke-Orchestration {
    param(
        [string]$ManifestPath = ".\manifests\manifest.psd1"
    )

    $Manifest = Read-OrchestrationManifest -Path $ManifestPath
    $Hosts    = $Manifest.Hosts
    $Steps    = $Manifest.Steps
    $Health   = $Manifest.HealthChecks

    foreach ($step in $Steps) {

        # Determine which hosts this step applies to
        $targetHosts = $Hosts | Where-Object { $step.Roles -contains $_.Role }

        Write-ProgressEvent -Phase 'Plan' -StepId $step.Id -HostName '*' `
            -Status 'Starting' -Detail "Targets: $($targetHosts.Name -join ', ')"

        # Execute step in parallel
        $results = Invoke-StepParallel -Hosts $targetHosts -Step $step

        # Log results
        foreach ($r in $results) {
            $status = if ($r.Exit -eq 0) { 'Success' } else { 'Failed' }
            Write-ProgressEvent -Phase 'Execute' -StepId $step.Id `
                -HostName $r.TargetHost -Status $status -Detail $r.StdErr
        }

        # Rollback trigger: ANY non-zero exit code
        if ($results.Exit -ne 0) {
            Write-ProgressEvent -Phase 'Execute' -StepId $step.Id `
                -HostName '*' -Status 'Error' -Detail 'Triggering rollback'

            # Log rollback start
            Write-ProgressEvent -Phase 'Rollback' -StepId $step.Id `
                -HostName '*' -Status 'Starting' -Detail 'Rolling back all steps'

            Invoke-Rollback -Hosts $Hosts -Steps $Steps
            return
        }
    }

    # Health checks
    $healthResults = Test-HostHealth -Hosts $Hosts -HealthChecks $Health
    $healthResults | ForEach-Object {
        Write-ProgressEvent -Phase 'Health' -StepId $_.CheckId `
            -HostName $_.Host -Status ($_.Success ? 'OK' : 'FAIL') `
            -Detail "Expected: $($_.Expected), Actual: $($_.Actual)"
    }
}
