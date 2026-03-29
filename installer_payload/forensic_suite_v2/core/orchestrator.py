import asyncio
import logging
import subprocess
import traceback
from pathlib import Path
from typing import Dict, List

import orjson
import yaml


class JsonLogger(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        try:
            ts = asyncio.get_running_loop().time()
        except RuntimeError:
            ts = 0.0

        base = {
            "msg": msg,
            "ts": ts,
            "component": "orchestrator",
        }
        if "extra" in kwargs:
            base.update(kwargs["extra"])
            del kwargs["extra"]
        return orjson.dumps(base).decode(), kwargs


log = JsonLogger(logging.getLogger("orchestrator"), {})

BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"


def load_monitored_services() -> List[str]:
    raw = yaml.safe_load(DEFAULT_CONFIG.read_text(encoding="utf-8")) or {}

    services: List[str] = []
    if raw.get("btc", {}).get("enabled", False):
        services.append("btc_indexer")
    if raw.get("eth", {}).get("enabled", False):
        services.append("eth_indexer")
    if raw.get("tron", {}).get("enabled", False):
        services.append("tron_indexer")

    return services


def _run_command(cmd: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def get_service_status(service_name: str) -> str:
    ps_cmd = (
        f"$svc = Get-Service -Name '{service_name}' -ErrorAction SilentlyContinue; "
        f"if ($null -eq $svc) {{ 'MISSING' }} else {{ $svc.Status.ToString().ToUpperInvariant() }}"
    )
    result = _run_command(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_cmd]
    )

    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        if stderr:
            log.error("Service status query failed", extra={"service": service_name, "stderr": stderr})
        return "ERROR"

    return (result.stdout or "").strip().upper() or "UNKNOWN"


def start_service(service_name: str) -> bool:
    result = _run_command(["sc", "start", service_name])

    if result.returncode != 0:
        log.error(
            "Failed to start service",
            extra={
                "service": service_name,
                "returncode": result.returncode,
                "stdout": (result.stdout or "").strip(),
                "stderr": (result.stderr or "").strip(),
            },
        )
        return False

    log.info("Start requested for service", extra={"service": service_name})
    return True


async def watchdog(interval: float = 10.0):
    monitored_services = load_monitored_services()

    while True:
        statuses: Dict[str, str] = {}

        for service_name in monitored_services:
            status = get_service_status(service_name)
            statuses[service_name] = status

            if status == "STOPPED":
                log.warning("Service stopped; requesting start", extra={"service": service_name, "status": status})
                start_service(service_name)
            elif status == "PAUSED":
                log.warning("Service paused; manual intervention required", extra={"service": service_name})
            elif status == "MISSING":
                log.warning("Service missing", extra={"service": service_name})
            elif status == "ERROR":
                log.warning("Service query error", extra={"service": service_name})
            elif status not in ("RUNNING", "START_PENDING"):
                log.warning("Unexpected service status", extra={"service": service_name, "status": status})

        log.info("Watchdog status", extra={"statuses": statuses})
        await asyncio.sleep(interval)


async def main():
    logging.basicConfig(level=logging.INFO)

    monitored = load_monitored_services()
    log.info(
        "Orchestrator starting",
        extra={
            "mode": "service-monitor",
            "monitored_services": monitored,
            "cwd": str(Path.cwd()),
        },
    )

    try:
        await watchdog()
    except asyncio.CancelledError:
        log.info("Orchestrator cancelled")
        raise
    except Exception as exc:
        log.error(
            "Orchestrator crashed",
            extra={"error": str(exc), "trace": traceback.format_exc()},
        )
        raise


if __name__ == "__main__":
    asyncio.run(main())
