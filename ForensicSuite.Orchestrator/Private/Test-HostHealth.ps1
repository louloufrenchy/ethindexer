function Test-HostHealth {
    param(
        [array]$Hosts,
        [array]$HealthChecks
    )

    foreach ($hc in $HealthChecks) {

        # Run the health check command on all hosts in parallel
        $results = Invoke-StepParallel -Hosts $Hosts -Step @{
            Type    = 'SSH'
            Command = $hc.Command
        }

        foreach ($r in $results) {
            $actual = $r.StdOut.Trim()
            $ok     = ($r.Exit -eq 0) -and ($actual -eq $hc.Expect)

            [pscustomobject]@{
                TargetHost = $r.TargetHost
                CheckId   = $hc.Id
                Expected  = $hc.Expect
                Actual    = $actual
                ExitCode  = $r.Exit
                Success   = $ok
            }
        }
    }
}
