# ForensicSecrets.psm1

function Get-ForensicConfigManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SuiteRoot = 'C:\forensic_suite_v2'
    )

    $manifestPath = Join-Path $SuiteRoot 'config\config.manifest.json'
    if (-not (Test-Path $manifestPath)) {
        throw "Config manifest not found at $manifestPath"
    }

    $json = Get-Content $manifestPath -Raw | ConvertFrom-Json
    return $json
}

function Sync-ForensicSecretsLocal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceSecretsRoot,
        [Parameter(Mandatory)]
        [string]$TargetSecretsRoot = 'C:\forensic_secrets'
    )

    if (-not (Test-Path $SourceSecretsRoot)) {
        throw "Source secrets root not found: $SourceSecretsRoot"
    }

    if (-not (Test-Path $TargetSecretsRoot)) {
        New-Item -ItemType Directory -Path $TargetSecretsRoot | Out-Null
    }

    Copy-Item -Path (Join-Path $SourceSecretsRoot '*') `
              -Destination $TargetSecretsRoot `
              -Recurse -Force
}

function Sync-ForensicSecretsRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetHost,

        [Parameter(Mandatory)]
        [string]$SourceSecretsRoot
    )

    if (-not (Test-Path $SourceSecretsRoot)) {
        throw "Source secrets root not found: $SourceSecretsRoot"
    }

    if (-not $Global:ForensicScp) {
        $Global:ForensicScp = "$env:WINDIR\System32\OpenSSH\scp.exe"
    }

    if (-not (Test-Path $Global:ForensicScp)) {
        throw "scp.exe not found: $Global:ForensicScp"
    }

    if (-not $Global:SSHKey) {
        throw "Global:SSHKey is not set."
    }

    if (-not (Test-Path $Global:SSHKey)) {
        throw "SSH key not found: $Global:SSHKey"
    }

    $script = @"
if (-not (Test-Path 'C:\forensic_secrets')) {
    New-Item -ItemType Directory -Path 'C:\forensic_secrets' -Force | Out-Null
}
"@

    Invoke-RemotePS -Host $TargetHost -Script $script | Out-Null

    $source = (Join-Path $SourceSecretsRoot '*')
    $destination = "forensicuser@${TargetHost}:C:/forensic_secrets/"

    & $Global:ForensicScp `
        -i $Global:SSHKey `
        -r `
        $source `
        $destination

    if ($LASTEXITCODE -ne 0) {
        throw ("scp failed while syncing secrets to {0}" -f $TargetHost)
    }
}

Export-ModuleMember -Function Get-ForensicConfigManifest, Sync-ForensicSecretsLocal, Sync-ForensicSecretsRemote
