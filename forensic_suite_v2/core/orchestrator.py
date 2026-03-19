import asyncio
import logging
import traceback
from pathlib import Path
from typing import Any, Dict
<<<<<<< HEAD

import yaml
import orjson

from forensic_suite_v2.tron_indexer.services.tron_indexer_service import TronIndexerService
from forensic_suite_v2.eth_indexer.services.eth_indexer_service import EthIndexerService
from forensic_suite_v2.btc_indexer.services.btc_indexer_service import BtcIndexerService


# -------------------------------------------------------------------
# Structured JSON Logger
# -------------------------------------------------------------------
=======
from types import SimpleNamespace

import orjson
import yaml

from forensic_suite_v2.btc_indexer.services.btc_indexer_service import BtcIndexerService
from forensic_suite_v2.eth_indexer.services.eth_indexer_service import EthIndexerService
from forensic_suite_v2.tron_indexer.services.tron_indexer_service import TronIndexerService


>>>>>>> master
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

<<<<<<< HEAD

# -------------------------------------------------------------------
# Config Loader
# -------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parents[2]
=======
BASE_DIR = Path(__file__).resolve().parents[1]
>>>>>>> master
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"


def load_config() -> Dict[str, Any]:
    with open(DEFAULT_CONFIG, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


<<<<<<< HEAD
# -------------------------------------------------------------------
# Supervisor Wrapper
# -------------------------------------------------------------------
async def supervised_task(name: str, service, restart_delay: float = 5.0):
    """
    Runs a chain indexer service with auto‑restart on failure.
    """
=======
def to_namespace(value: Any) -> Any:
    if isinstance(value, dict):
        return SimpleNamespace(**{k: to_namespace(v) for k, v in value.items()})
    if isinstance(value, list):
        return [to_namespace(v) for v in value]
    return value


async def supervised_task(name: str, service, restart_delay: float = 5.0):
>>>>>>> master
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


<<<<<<< HEAD
# -------------------------------------------------------------------
# Watchdog
# -------------------------------------------------------------------
=======
>>>>>>> master
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


<<<<<<< HEAD
# -------------------------------------------------------------------
# Main Orchestrator
# -------------------------------------------------------------------
async def main():
    logging.basicConfig(level=logging.INFO)

    cfg = load_config()
    chains = cfg.get("chains", ["tron"])
=======
async def main():
    logging.basicConfig(level=logging.INFO)

    raw_cfg = load_config()
    cfg = to_namespace(raw_cfg)

    chains = raw_cfg.get("chains", ["tron"])
>>>>>>> master

    log.info("Orchestrator starting", extra={"chains": chains})

    tasks: Dict[str, asyncio.Task] = {}

<<<<<<< HEAD
    # TRON
    if "tron" in chains:
        tron_service = TronIndexerService(cfg)
=======
    if "tron" in chains and getattr(cfg, "tron", None) and getattr(cfg.tron, "enabled", True):
        tron_service = TronIndexerService(cfg.tron)
>>>>>>> master
        tasks["tron"] = asyncio.create_task(
            supervised_task("tron", tron_service), name="tron_supervisor"
        )

<<<<<<< HEAD
    # ETH
    if "eth" in chains:
        eth_service = EthIndexerService(cfg)
=======
    if "eth" in chains and getattr(cfg, "eth", None) and getattr(cfg.eth, "enabled", True):
        eth_service = EthIndexerService(cfg.eth)
>>>>>>> master
        tasks["eth"] = asyncio.create_task(
            supervised_task("eth", eth_service), name="eth_supervisor"
        )

<<<<<<< HEAD
    # BTC
    if "btc" in chains:
        btc_service = BtcIndexerService(cfg)
=======
    if "btc" in chains and getattr(cfg, "btc", None) and getattr(cfg.btc, "enabled", True):
        btc_service = BtcIndexerService(cfg.btc)
>>>>>>> master
        tasks["btc"] = asyncio.create_task(
            supervised_task("btc", btc_service), name="btc_supervisor"
        )

    if not tasks:
        log.error("No chains enabled — nothing to run")
        return

<<<<<<< HEAD
    # Watchdog
=======
>>>>>>> master
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