function Invoke-SSH {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetHost,

        [Parameter(Mandatory)]
        [string]$Command,

        [int]$TimeoutSeconds = 120
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = 'ssh.exe'
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.RedirectStandardInput  = $true   # ⭐ FIX: close STDIN
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $sshTarget = "forensicuser@$TargetHost"
    $escaped   = $Command.Replace('"','\"')
    $psi.Arguments = "-i `"$env:USERPROFILE\.ssh\id_ed25519`" $sshTarget `"$escaped`""

    Write-Host "[DEBUG] SSH Arguments: $($psi.Arguments)" -ForegroundColor Yellow

    $proc = [System.Diagnostics.Process]::Start($psi)

    # ⭐ FIX: close STDIN so ssh.exe doesn't hang
    $proc.StandardInput.Close()

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill() } catch {}
        return [pscustomobject]@{
            TargetHost = $TargetHost
            Exit       = 255
            StdOut     = $proc.StandardOutput.ReadToEnd()
            StdErr     = "Timeout after $TimeoutSeconds seconds. STDERR: $($proc.StandardError.ReadToEnd())"
        }
    }

    return [pscustomobject]@{
        TargetHost = $TargetHost
        Exit       = $proc.ExitCode
        StdOut     = $proc.StandardOutput.ReadToEnd()
        StdErr     = $proc.StandardError.ReadToEnd()
    }
}
