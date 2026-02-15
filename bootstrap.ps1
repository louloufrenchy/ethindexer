param(
    [string]$Root = "C:\development\forensic_tracer_installer_project_root"
)

Write-Host "Bootstrap starting for root: $Root" -ForegroundColor Cyan

$folders = @(
    "$Root\installer_payload",
    "$Root\manifests",
    "$Root\logs",
    "$Root\dashboards",
    "$Root\tests",
    "$Root\ForensicSuite.Orchestrator\Public",
    "$Root\ForensicSuite.Orchestrator\Private"
)

foreach ($f in $folders) {
    if (-not (Test-Path $f)) {
        Write-Host "Creating folder: $f"
        New-Item -ItemType Directory -Path $f | Out-Null
    }
}

# Sample manifest
$manifestPath = "$Root\manifests\manifest.psd1"
if (-not (Test-Path $manifestPath)) {
@'
@{
    Hosts = @(
        @{
            Name    = 'WIN-1V7900SUQ9A'
            Address = '192.168.0.199'
            Role    = 'Collector'
        },
        @{
            Name    = 'WIN-U0AR3HQSOJB'
            Address = '192.168.0.146'
            Role    = 'Controller'
        },
        @{
            Name    = 'WIN-8ENVN7I0JFE'
            Address = '192.168.0.165'
            Role    = 'DB'
        }
    )

    Steps = @(
        @{
            Id         = 'UploadInstaller'
            Type       = 'SCP'
            Artifact   = 'installer_payload\ForensicSuiteV2-setup.exe'
            RemotePath = 'C:\Temp\ForensicSuiteV2-setup.exe'
            Roles      = @('Collector','Controller','DB')
            Rollback   = @{
                Type = 'DeleteFile'
                Path = 'C:\Temp\ForensicSuiteV2-setup.exe'
            }
        },
        @{
            Id       = 'RunInstaller'
            Type     = 'SSH'
            Command  = 'C:\Temp\ForensicSuiteV2-setup.exe /silent /log=C:\Temp\fs_install.log'
            Roles    = @('Collector','Controller','DB')
            Rollback = @{
                Type    = 'SSH'
                Command = 'C:\Program Files\ForensicSuiteV2\unins000.exe /silent'
            }
        },
        @{
            Id      = 'PostHealthCheck'
            Type    = 'SSH'
            Command = 'powershell -NoProfile -Command "Get-Service ForensicSuiteV2 | Select-Object Status,Name"'
            Roles   = @('Collector','Controller','DB')
            Rollback = $null
        }
    )

    HealthChecks = @(
        @{
            Id      = 'ServiceRunning'
            Command = 'powershell -NoProfile -Command "Get-Service ForensicSuiteV2 | Select-Object -ExpandProperty Status"'
            Expect  = 'Running'
        }
    )
}
'@ | Set-Content -Path $manifestPath -Encoding UTF8
    Write-Host "Created sample manifest: $manifestPath"
}

# Module manifest
$moduleRoot = "$Root\ForensicSuite.Orchestrator"
$psd1Path   = "$moduleRoot\ForensicSuite.Orchestrator.psd1"
if (-not (Test-Path $psd1Path)) {
@'
@{
    RootModule        = 'ForensicSuite.Orchestrator.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'd3b0c1c4-8f3e-4c7e-9c7c-123456789abc'
    Author            = 'Louis'
    CompanyName       = 'ForensicSuite'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Invoke-Orchestration',
        'Read-OrchestrationManifest'
    )
    PrivateData       = @{}
}
'@ | Set-Content -Path $psd1Path -Encoding UTF8
    Write-Host "Created module manifest: $psd1Path"
}

# Module psm1
$psm1Path = "$moduleRoot\ForensicSuite.Orchestrator.psm1"
if (-not (Test-Path $psm1Path)) {
@'
# Public
. $PSScriptRoot\Public\Invoke-Orchestration.ps1
. $PSScriptRoot\Public\Read-OrchestrationManifest.ps1

# Private
. $PSScriptRoot\Private\Invoke-SSH.ps1
. $PSScriptRoot\Private\Invoke-SCP.ps1
. $PSScriptRoot\Private\Invoke-StepParallel.ps1
. $PSScriptRoot\Private\Invoke-Rollback.ps1
. $PSScriptRoot\Private\Test-HostHealth.ps1
. $PSScriptRoot\Private\Write-ProgressEvent.ps1
'@ | Set-Content -Path $psm1Path -Encoding UTF8
    Write-Host "Created module root: $psm1Path"
}

# Public functions
$publicFiles = @{
    "Invoke-Orchestration.ps1" = @'
function Invoke-Orchestration {
    param(
        [string]$ManifestPath = ".\manifests\manifest.psd1"
    )

    $Manifest = Read-OrchestrationManifest -Path $ManifestPath
    $Hosts    = $Manifest.Hosts
    $Steps    = $Manifest.Steps
    $Health   = $Manifest.HealthChecks

    foreach ($step in $Steps) {
        $targetHosts = $Hosts | Where-Object { $step.Roles -contains $_.Role }

        Write-ProgressEvent -Phase 'Plan' -StepId $step.Id -HostName '*' -Status 'Starting' -Detail "Targets: $($targetHosts.Name -join ', ')"

        $results = Invoke-StepParallel -Hosts $targetHosts -Step $step

        foreach ($r in $results) {
            $status = if ($r.Exit -eq 0) { 'Success' } else { 'Failed' }
            Write-ProgressEvent -Phase 'Execute' -StepId $step.Id -HostName $r.Host -Status $status -Detail $r.StdErr
        }

        if ($results.Exit -contains 1..65535) {
            Write-ProgressEvent -Phase 'Execute' -StepId $step.Id -HostName '*' -Status 'Error' -Detail 'Triggering rollback'
            Invoke-Rollback -Hosts $Hosts -Steps $Steps
            return
        }
    }

    $healthResults = Test-HostHealth -Hosts $Hosts -HealthChecks $Health
    $healthResults | ForEach-Object {
        Write-ProgressEvent -Phase 'Health' -StepId $_.CheckId -HostName $_.Host -Status ($_.Success ? 'OK' : 'FAIL') -Detail "Expected: $($_.Expected), Actual: $($_.Actual)"
    }
}
'@
    "Read-OrchestrationManifest.ps1" = @'
function Read-OrchestrationManifest {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Manifest not found: $Path"
    }

    Import-PowerShellDataFile -Path $Path
}
'@
}

foreach ($name in $publicFiles.Keys) {
    $path = "$Root\ForensicSuite.Orchestrator\Public\$name"
    if (-not (Test-Path $path)) {
        $publicFiles[$name] | Set-Content -Path $path -Encoding UTF8
        Write-Host "Created public function: $path"
    }
}

# Private functions
$privateFiles = @{
    "Invoke-SSH.ps1" = @'
function Invoke-SSH {
    param(
        [string]$Host,
        [string]$Command,
        [int]$TimeoutSeconds = 120
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = 'ssh.exe'
    $psi.Arguments = "-i `"$env:USERPROFILE\.ssh\id_ed25519`" forensicuser@$Host `"$Command`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        $proc.Kill()
        return [pscustomobject]@{
            Host   = $Host
            Exit   = 255
            StdOut = ''
            StdErr = "Timeout after $TimeoutSeconds seconds"
        }
    }

    [pscustomobject]@{
        Host   = $Host
        Exit   = $proc.ExitCode
        StdOut = $proc.StandardOutput.ReadToEnd()
        StdErr = $proc.StandardError.ReadToEnd()
    }
}
'@
    "Invoke-SCP.ps1" = @'
function Invoke-SCP {
    param(
        [string]$Host,
        [string]$LocalPath,
        [string]$RemotePath
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = 'scp.exe'
    $psi.Arguments = "-i `"$env:USERPROFILE\.ssh\id_ed25519`" `"$LocalPath`" forensicuser@$Host:`"$RemotePath`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()

    [pscustomobject]@{
        Host   = $Host
        Exit   = $proc.ExitCode
        StdOut = $proc.StandardOutput.ReadToEnd()
        StdErr = $proc.StandardError.ReadToEnd()
    }
}
'@
    "Invoke-StepParallel.ps1" = @'
function Invoke-StepParallel {
    param(
        [array]$Hosts,
        [hashtable]$Step
    )

    $jobs = foreach ($h in $Hosts) {
        Start-Job -ScriptBlock {
            param($Host, $Step)

            switch ($Step.Type) {
                'SCP' {
                    Invoke-SCP -Host $Host.Address -LocalPath $Step.Artifact -RemotePath $Step.RemotePath
                }
                'SSH' {
                    Invoke-SSH -Host $Host.Address -Command $Step.Command
                }
            }
        } -ArgumentList $h, $Step
    }

    Receive-Job -Job $jobs -Wait -AutoRemoveJob
}
'@
    "Invoke-Rollback.ps1" = @'
function Invoke-Rollback {
    param(
        [array]$Hosts,
        [array]$Steps
    )

    foreach ($h in $Hosts) {
        foreach ($step in $Steps | Sort-Object Id -Descending) {
            if (-not $step.Rollback) { continue }

            switch ($step.Rollback.Type) {
                'DeleteFile' {
                    Invoke-SSH -Host $h.Address -Command "del `"$($step.Rollback.Path)`" /f /q"
                }
                'SSH' {
                    Invoke-SSH -Host $h.Address -Command $step.Rollback.Command
                }
            }
        }
    }
}
'@
    "Test-HostHealth.ps1" = @'
function Test-HostHealth {
    param(
        [array]$Hosts,
        [array]$HealthChecks
    )

    foreach ($hc in $HealthChecks) {
        $results = Invoke-StepParallel -Hosts $Hosts -Step @{
            Type    = 'SSH'
            Command = $hc.Command
        }

        foreach ($r in $results) {
            $ok = $r.Exit -eq 0 -and $r.StdOut.Trim() -eq $hc.Expect
            [pscustomobject]@{
                Host      = $r.Host
                CheckId   = $hc.Id
                Expected  = $hc.Expect
                Actual    = $r.StdOut.Trim()
                ExitCode  = $r.Exit
                Success   = $ok
            }
        }
    }
}
'@
    "Write-ProgressEvent.ps1" = @'
function Write-ProgressEvent {
    param(
        [string]$Phase,
        [string]$StepId,
        [string]$HostName,
        [string]$Status,
        [string]$Detail
    )

    if (-not (Test-Path ".\logs")) {
        New-Item -ItemType Directory -Path ".\logs" | Out-Null
    }

    $event = [pscustomobject]@{
        Time    = Get-Date
        Phase   = $Phase
        StepId  = $StepId
        Host    = $HostName
        Status  = $Status
        Detail  = $Detail
    }

    $event | ConvertTo-Json -Depth 5 | Add-Content -Path ".\logs\orchestrator.log.json"

    Write-Host ("[{0}] {1} | {2} | {3} | {4}" -f $event.Time, $Phase, $StepId, $HostName, $Status)
}
'@
}

foreach ($name in $privateFiles.Keys) {
    $path = "$Root\ForensicSuite.Orchestrator\Private\$name"
    if (-not (Test-Path $path)) {
        $privateFiles[$name] | Set-Content -Path $path -Encoding UTF8
        Write-Host "Created private function: $path"
    }
}

# Dry-run test
$dryRunPath = "$Root\tests\dryrun.ps1"
if (-not (Test-Path $dryRunPath)) {
@'
Import-Module ..\ForensicSuite.Orchestrator

Write-Host "=== DRY RUN MODE ===" -ForegroundColor Cyan

$Manifest = Read-OrchestrationManifest -Path ..\manifests\manifest.psd1

foreach ($step in $Manifest.Steps) {
    $targets = $Manifest.Hosts | Where-Object { $step.Roles -contains $_.Role } | Select-Object -ExpandProperty Name -join ', '
    Write-Host "Would execute step: $($step.Id)"
    Write-Host "  Type: $($step.Type)"
    Write-Host "  Targets: $targets"
    Write-Host ""
}

Write-Host "Dry run complete."
'@ | Set-Content -Path $dryRunPath -Encoding UTF8
    Write-Host "Created dry-run test: $dryRunPath"
}

Write-Host "Bootstrap complete." -ForegroundColor Green
