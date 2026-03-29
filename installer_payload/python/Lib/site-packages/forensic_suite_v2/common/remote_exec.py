import asyncio
import shlex

async def run_ssh(host: str, command: str, timeout: int = 10) -> tuple[int, str, str]:
    """
    Executes a PowerShell command on a remote Windows host via SSH.
    Returns (exit_code, stdout, stderr).
    """

    # IMPORTANT: wrap the remote command in double quotes
    # and escape internal quotes for PowerShell.
    safe_cmd = command.replace('"', '\\"')

    ssh_cmd = [
        "ssh",
        f"forensicuser@{host}",
        f'powershell -NoProfile -ExecutionPolicy Bypass -Command "{safe_cmd}"'
    ]

    proc = await asyncio.create_subprocess_exec(
        *ssh_cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )

    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        return (1, "", "TIMEOUT")

    return (proc.returncode, stdout.decode(errors="ignore"), stderr.decode(errors="ignore"))

async def get_service_status(host: str, service_name: str) -> str:
    cmd = (
        f"$svc = Get-Service -Name '{service_name}' -ErrorAction SilentlyContinue; "
        f"if ($null -eq $svc) {{ 'MISSING' }} else {{ $svc.Status.ToString().ToUpperInvariant() }}"
    )

    code, out, err = await run_ssh(host, cmd)

    if code != 0:
        return "ERROR"

    return out.strip() or "UNKNOWN"
