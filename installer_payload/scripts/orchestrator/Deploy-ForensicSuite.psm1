# Deploy-ForensicSuite.psm1

$Script:PrivateKey = "$env:USERPROFILE\.ssh\id_ed25519"
$Script:SshUser    = "forensicuser"
$Script:InstallerLocalPath = "C:\development\forensic_tracer_installer_project_root\installer_payload\ForensicSuiteV2-Setup.exe"
$Script:RemoteInstallerPath = "C:\Temp\ForensicSuiteV2-Setup.exe"

function Invoke-Ssh {
    param(
        [string]$Host,
        [string]$Command
    )

    $args = @(
        "-i", $Script:PrivateKey,
        "$($Script:SshUser)@$Host",
        $Command
    )

    Write-Host "[DEBUG] SSH Arguments: $($args -join ' ')" -ForegroundColor DarkGray
    & ssh @args
    return $LASTEXITCODE
}

function Copy-InstallerSCP {
    param(
        [string]$Host
    )

    $args = @(
        "-i", $Script:PrivateKey,
        $Script:InstallerLocalPath,
        "$($Script:SshUser)@$Host:`"$($Script:RemoteInstallerPath)`""
    )

    Write-Host "[DEBUG] SCP Arguments: $($args -join ' ')" -ForegroundColor DarkGray
    & scp @args
    return $LASTEXITCODE
}

function Ensure-RemoteTemp {
    param(
        [string]$Host
    )

    $cmd = 'powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path C:\Temp | Out-Null"'
    Invoke-Ssh -Host $Host -Command $cmd
}

function Install-ForensicSuite {
    param(
        [string]$Host
    )

    $cmd = 'powershell -NoProfile -Command "Start-Process -FilePath ''C:\Temp\ForensicSuiteV2-Setup.exe'' -ArgumentList ''/VERYSILENT'' -Wait -PassThru | Out-Null"'
    Invoke-Ssh -Host $Host -Command $cmd
}

function Uninstall-ForensicSuite {
    param(
        [string]$Host
    )

    $cmd = 'powershell -NoProfile -Command "if (Test-Path ''C:\Program Files\ForensicSuiteV2\unins000.exe'') { Start-Process -FilePath ''C:\Program Files\ForensicSuiteV2\unins000.exe'' -ArgumentList ''/VERYSILENT'' -Wait -PassThru | Out-Null }"'
    Invoke-Ssh -Host $Host -Command $cmd
}

function Cleanup-RemoteInstaller {
    param(
        [string]$Host
    )

    $cmd = 'powershell -NoProfile -Command "if (Test-Path ''C:\Temp\ForensicSuiteV2-Setup.exe'') { Remove-Item -Force ''C:\Temp\ForensicSuiteV2-Setup.exe'' }"'
    Invoke-Ssh -Host $Host -Command $cmd
}
