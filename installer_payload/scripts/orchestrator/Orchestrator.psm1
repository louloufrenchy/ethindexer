# Orchestrator.psm1 — Stable Minimal Version
# Requires -Version 7.0
using namespace System.Management.Automation.Runspaces
. $PSScriptRoot\Invoke-ForensicDeployment.ps1

# ------------------------------------------------------------
# Manifest loading
# ------------------------------------------------------------
$Script:ManifestPath = Join-Path $PSScriptRoot 'deployment_manifest.json'
$Script:Manifest     = Get-Content $Script:ManifestPath -Raw | ConvertFrom-Json

$Script:SshUser             = $Script:Manifest.ssh_user
$Script:SshKey              = $ExecutionContext.InvokeCommand.ExpandString($Script:Manifest.ssh_key)
$Script:InstallerLocalPath  = $Script:Manifest.installer_local_path
$Script:RemoteInstallerPath = $Script:Manifest.remote_installer_path
$Script:Hosts               = $Script:Manifest.hosts

# ------------------------------------------------------------
# SSH wrapper
# ------------------------------------------------------------
function Invoke-Ssh {
    param([string]$TargetHost, [string]$Command)

    $args = @(
        "-o","BatchMode=yes"
        "-o","ConnectTimeout=10"
        "-i",$Script:SshKey
        "$($Script:SshUser)@$TargetHost"
        $Command
    )

    $p = Start-Process ssh -ArgumentList $args -NoNewWindow -PassThru -Wait
    return $p.ExitCode
}

# ------------------------------------------------------------
# SCP wrapper
# ------------------------------------------------------------
function Invoke-Scp {
    param([string]$TargetHost,[string]$LocalPath,[string]$RemotePath)

    $remote = "$($Script:SshUser)@${TargetHost}:$RemotePath"
    & scp -i $Script:SshKey $LocalPath $remote
    return $LASTEXITCODE
}

# ------------------------------------------------------------
# Parallel engine
# ------------------------------------------------------------
function Invoke-Parallel {
    param(
        [string]$ActionName,
        [string]$StepName,
        [int]$MaxDegreeOfParallelism = 8
    )

    Write-Host ""
    Write-Host "=== $StepName ===" -ForegroundColor Cyan

    $modulePath = Join-Path $PSScriptRoot 'Orchestrator.psm1'

    $pool = [RunspaceFactory]::CreateRunspacePool(1,$MaxDegreeOfParallelism)
    $pool.Open()

    $tasks=@()
    $results=@()

    foreach ($h in $Script:Hosts) {
        $ps=[powershell]::Create()
        $ps.RunspacePool=$pool

        $null = $ps.AddScript({
            param($TargetHost,$ActionName,$ModulePath)

            Import-Module $ModulePath -Force

            try {
                $exitCode = & $ActionName $TargetHost
            }
            catch {
                $exitCode = -1
            }

            [pscustomobject]@{
                Host     = $TargetHost
                ExitCode = $exitCode
            }
        }).AddArgument($h.ip).AddArgument($ActionName).AddArgument($modulePath)

        $handle=$ps.BeginInvoke()

        $tasks += [pscustomobject]@{
            PS=$ps
            Handle=$handle
            Host=$h.ip
        }
    }

    while ($tasks.Count -gt 0) {
        foreach ($t in @($tasks)) {
            if ($t.Handle.IsCompleted) {
                $data=$t.PS.EndInvoke($t.Handle)
                $t.PS.Dispose()
                $results+=$data

                $color = if ($data.ExitCode -eq 0) {"Green"} else {"Red"}
                Write-Host ("[{0}] Exit={1}" -f $data.Host,$data.ExitCode) -ForegroundColor $color

                $tasks = $tasks | Where-Object { $_ -ne $t }
            }
        }
        Start-Sleep -Milliseconds 100
    }

    $pool.Close()
    $pool.Dispose()

    return @{
        Success = ($results.ExitCode -notcontains -1)
        Results = $results
    }
}

# ------------------------------------------------------------
# Deployment actions
# ------------------------------------------------------------
function Ensure-RemoteTemp {
    param([string]$TargetHost)
    $cmd = "pwsh -NoProfile -Command New-Item -ItemType Directory -Force -Path 'C:\Temp' | Out-Null"
    Invoke-Ssh $TargetHost $cmd
}

function Upload-Installer {
    param([string]$TargetHost)
    Invoke-Scp $TargetHost $Script:InstallerLocalPath $Script:RemoteInstallerPath
}

function Install-ForensicSuite {
    param([string]$TargetHost)
    $cmd = "pwsh -NoProfile -Command Start-Process -FilePath 'C:\Temp\ForensicSuiteV2-Setup.exe' -ArgumentList '/VERYSILENT' -Wait -PassThru | Out-Null"
    Invoke-Ssh $TargetHost $cmd
}

function Uninstall-ForensicSuite {
    param([string]$TargetHost)

    $cmd = "pwsh -NoProfile -Command `"if (Test-Path 'C:\Program Files\ForensicSuiteV2\unins000.exe') { Start-Process -FilePath 'C:\Program Files\ForensicSuiteV2\unins000.exe' -ArgumentList '/VERYSILENT' -Wait -PassThru | Out-Null }`""

    Invoke-Ssh $TargetHost $cmd
}

function Cleanup-Installer {
    param([string]$TargetHost)

    $cmd = "pwsh -NoProfile -Command `"if (Test-Path 'C:\Temp\ForensicSuiteV2-Setup.exe') { Remove-Item -Force 'C:\Temp\ForensicSuiteV2-Setup.exe' }`""

    Invoke-Ssh $TargetHost $cmd
}

function HealthCheck {
    param([string]$TargetHost)

    $cmd = "pwsh -NoProfile -Command `"if (Test-Path 'C:\Program Files\ForensicSuiteV2\ForensicSuite.exe') { exit 0 } else { exit 1 }`""
    Invoke-Ssh $TargetHost $cmd
}

# ------------------------------------------------------------
# Step wrapper
# ------------------------------------------------------------
function Invoke-Step {
    param(
        [string]$Name,
        [string]$ActionName,
        [string]$RollbackActionName
    )

    $result = Invoke-Parallel -ActionName $ActionName -StepName $Name

    if (-not $result.Success) {
        Write-Host "Step '$Name' failed." -ForegroundColor Red
        if ($RollbackActionName) {
            Invoke-Parallel -ActionName $RollbackActionName -StepName "$Name-Rollback" | Out-Null
        }
        return $false
    }

    Write-Host "Step '$Name' succeeded." -ForegroundColor Green
    return $true
}

Export-ModuleMember -Function Invoke-ForensicDeployment
