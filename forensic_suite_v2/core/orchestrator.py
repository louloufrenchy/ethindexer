import asyncio
import logging
import traceback
from pathlib import Path
from typing import Any, Dict

import yaml
import orjson

from forensic_suite_v2.tron_indexer.services.tron_indexer_service import TronIndexerService
from forensic_suite_v2.eth_indexer.services.eth_indexer_service import EthIndexerService
from forensic_suite_v2.btc_indexer.services.btc_indexer_service import BtcIndexerService


# -------------------------------------------------------------------
# Structured JSON Logger
# -------------------------------------------------------------------
class JsonLogger(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        base = {
            "msg": msg,
            "ts": asyncio.get_event_loop().time(),
            "component": "orchestrator",
        }
        if "extra" in kwargs:
            base.update(kwargs["extra"])
            del kwargs["extra"]
        return orjson.dumps(base).decode(), kwargs


log = JsonLogger(logging.getLogger("orchestrator"), {})


# -------------------------------------------------------------------
# Config Loader
# -------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"


def load_config() -> Dict[str, Any]:
    with open(DEFAULT_CONFIG, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# -------------------------------------------------------------------
# Supervisor Wrapper
# -------------------------------------------------------------------
async def supervised_task(name: str, service, restart_delay: float = 5.0):
    """
    Runs a chain indexer service with auto‑restart on failure.
    """
    while True:
        try:
            log.info("Starting chain service", extra={"chain": name})
            await service.run()
        except asyncio.CancelledError:
            log.info("Supervisor cancelled", extra={"chain": name})
            break
        except Exception as e:
            log.error(
                "Chain crashed",
                extra={"chain": name, "error": str(e), "trace": traceback.format_exc()},
            )
            log.info("Restarting chain soon", extra={"chain": name, "delay": restart_delay})
            await asyncio.sleep(restart_delay)


# -------------------------------------------------------------------
# Watchdog
# -------------------------------------------------------------------
async def watchdog(tasks: Dict[str, asyncio.Task], interval: float = 10.0):
    while True:
        await asyncio.sleep(interval)
        statuses = {}
        for name, task in tasks.items():
            if task.cancelled():
                statuses[name] = "CANCELLED"
            elif task.done():
                statuses[name] = "DONE"
            else:
                statuses[name] = "RUNNING"

        log.info("Watchdog status", extra={"statuses": statuses})


# -------------------------------------------------------------------
# Main Orchestrator
# -------------------------------------------------------------------
async def main():
    logging.basicConfig(level=logging.INFO)

    cfg = load_config()
    chains = cfg.get("chains", ["tron"])

    log.info("Orchestrator starting", extra={"chains": chains})

    tasks: Dict[str, asyncio.Task] = {}

    # TRON
    if "tron" in chains:
        tron_service = TronIndexerService(cfg)
        tasks["tron"] = asyncio.create_task(
            supervised_task("tron", tron_service), name="tron_supervisor"
        )

    # ETH
    if "eth" in chains:
        eth_service = EthIndexerService(cfg)
        tasks["eth"] = asyncio.create_task(
            supervised_task("eth", eth_service), name="eth_supervisor"
        )

    # BTC
    if "btc" in chains:
        btc_service = BtcIndexerService(cfg)
        tasks["btc"] = asyncio.create_task(
            supervised_task("btc", btc_service), name="btc_supervisor"
        )

    if not tasks:
        log.error("No chains enabled — nothing to run")
        return

    # Watchdog
    wd = asyncio.create_task(watchdog(tasks), name="orchestrator_watchdog")

    try:
        await asyncio.gather(*tasks.values())
    except asyncio.CancelledError:
        log.info("Orchestrator cancelled")
    finally:
        wd.cancel()
        try:
            await wd
        except asyncio.CancelledError:
            pass


if __name__ == "__main__":
    asyncio.run(main())