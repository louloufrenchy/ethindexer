from __future__ import annotations

import asyncio
import base64


def _encode_powershell(command: str) -> str:
    raw = command.encode("utf-16le")
    return base64.b64encode(raw).decode("ascii")


async def run_ssh(host: str, command: str, timeout: int = 10):
    """
    Execute a PowerShell command on a remote Windows host over SSH.

    Returns:
        (returncode, stdout, stderr)
    """
    encoded = _encode_powershell(command)

    ssh_cmd = [
        "ssh",
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=no",
        f"forensicuser@{host}",
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-EncodedCommand",
        encoded,
    ]

    proc = await asyncio.create_subprocess_exec(
        *ssh_cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        try:
            await proc.communicate()
        except Exception:
            pass
        return (1, "", "TIMEOUT")

    return (
        proc.returncode,
        stdout.decode(errors="replace"),
        stderr.decode(errors="replace"),
    )
