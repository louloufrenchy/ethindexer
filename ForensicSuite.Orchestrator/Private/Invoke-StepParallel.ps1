function Invoke-StepParallel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Hosts,

        [Parameter(Mandatory)]
        [pscustomobject]$Step
    )

    $jobs = @()

    $modulePath = (Get-Module ForensicSuite.Orchestrator).Path
    $moduleRoot = Split-Path $modulePath -Parent

    foreach ($Host in $Hosts) {

        $TargetHost = $Host.Address

        switch ($Step.Type) {

            'SSH' {
                # --- SSH step: encode command and call Invoke-SSH in the job ---

                $encoded = [Convert]::ToBase64String(
                    [Text.Encoding]::Unicode.GetBytes($Step.Command)
                )

                $job = Start-Job -ScriptBlock {
                    param($TargetHost, $EncodedCommand, $ModuleRoot)

                    Import-Module (Join-Path $ModuleRoot 'ForensicSuite.Orchestrator.psd1') -Force

                    $decoded = [Text.Encoding]::Unicode.GetString(
                        [Convert]::FromBase64String($EncodedCommand)
                    )

                    Invoke-SSH -TargetHost $TargetHost -Command $decoded

                } -ArgumentList $TargetHost, $encoded, $moduleRoot
            }

            'SCP' {
                # --- SCP step: no command, just copy the artifact ---

                $localPath  = $Step.Artifact
                $remotePath = $Step.RemotePath

                $job = Start-Job -ScriptBlock {
                    param($TargetHost, $LocalPath, $RemotePath, $ModuleRoot)

                    Import-Module (Join-Path $ModuleRoot 'ForensicSuite.Orchestrator.psd1') -Force

                    Invoke-SCP -TargetHost $TargetHost -LocalPath $LocalPath -RemotePath $RemotePath

                } -ArgumentList $TargetHost, $Step.Artifact, $Step.RemotePath, $moduleRoot
            }

            default {
                throw "Unsupported step type '$($Step.Type)' in Invoke-StepParallel."
            }
        }

        $jobs += $job
    }

    if (-not $jobs) {
        return @()
    }

    $completed = $jobs | Wait-Job
    $results   = $completed | Receive-Job
    $completed | Remove-Job -Force

    return $results
}
