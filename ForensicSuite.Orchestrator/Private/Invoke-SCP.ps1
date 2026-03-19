function Invoke-SCP {
    param(
        [string]$TargetHost,
        [string]$LocalPath,
        [string]$RemotePath
    )

    # Convert relative path → absolute path
    $LocalPath = (Resolve-Path $LocalPath).Path

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = 'scp.exe'

    $scpTarget = "forensicuser@${TargetHost}:${RemotePath}"

    $psi.Arguments = "-i `"$env:USERPROFILE\.ssh\id_ed25519`" `"$LocalPath`" `"$scpTarget`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()

    return [pscustomobject]@{
        TargetHost = $TargetHost
        Exit       = $proc.ExitCode
        StdOut     = $proc.StandardOutput.ReadToEnd()
        StdErr     = $proc.StandardError.ReadToEnd()
    }
}
