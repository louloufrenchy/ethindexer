from pathlib import Path
import os
import yaml
import asyncio
import logging
import traceback
import time

from tron_indexer.services.run_tron_indexer_v2 import TronQuickNodeIndexerV2
from tron_indexer.services.run_eth_indexer_v2 import EthIndexerV2
from tron_indexer.services.run_btc_indexer_v2 import BtcIndexerV2

BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"
CONFIG_PATH = os.environ.get("CONFIG_PATH", str(DEFAULT_CONFIG))

log = logging.getLogger("orchestrator")


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def healthcheck_config():
    cfg_path = Path(CONFIG_PATH)
    if not cfg_path.exists():
        raise FileNotFoundError(f"[HEALTHCHECK] Config not found at: {cfg_path}")
    print(f"[HEALTHCHECK] Config OK → {cfg_path}")
    log.info("Config OK → %s", cfg_path)


async def healthcheck_chain(name: str, cfg: dict) -> bool:
    """
    Lightweight per-chain healthcheck hook.
    For now: just validates required sections exist.
    You can extend this to do DB pings, RPC pings, etc.
    """
    try:
        if name == "tron":
            assert "tron_rpc" in cfg, "tron_rpc missing"
        elif name == "eth":
            assert "eth_rpc" in cfg, "eth_rpc missing"
        elif name == "btc":
            assert "btc_rpc" in cfg, "btc_rpc missing"
        log.info("[HEALTHCHECK][%s] OK", name.upper())
        return True
    except Exception as e:
        log.error("[HEALTHCHECK][%s] FAILED: %s", name.upper(), e)
        return False


async def run_tron(cfg):
    try:
        indexer = TronQuickNodeIndexerV2(cfg)
        log.info("[ORCH][TRON] Starting TRON indexer…")
        await indexer.run()
    except Exception as e:
        log.error("[ORCH][TRON] Fatal error: %s", e)
        log.debug("[ORCH][TRON] Traceback:\n%s", traceback.format_exc())
        raise


async def run_eth(cfg):
    try:
        indexer = EthIndexerV2(cfg)
        log.info("[ORCH][ETH] Starting ETH indexer…")
        await indexer.run()
    except Exception as e:
        log.error("[ORCH][ETH] Fatal error: %s", e)
        log.debug("[ORCH][ETH] Traceback:\n%s", traceback.format_exc())
        raise


async def run_btc(cfg):
    try:
        indexer = BtcIndexerV2(cfg)
        log.info("[ORCH][BTC] Starting BTC indexer…")
        await indexer.run()
    except Exception:
        log.error("[ORCH][BTC] Fatal error, full traceback:")
        log.error(traceback.format_exc())
        raise


async def supervised_task(name: str, coro_factory, cfg, restart_delay: float = 5.0):
    """
    Graceful restart loop for a single chain.
    If the indexer crashes, we log and restart after a delay.
    """
    while True:
        try:
            log.info("[ORCH][%s] Supervisor starting indexer…", name.upper())
            await coro_factory(cfg)
        except asyncio.CancelledError:
            log.info("[ORCH][%s] Supervisor cancelled, shutting down.", name.upper())
            break
        except Exception as e:
            log.error("[ORCH][%s] Indexer crashed: %s", name.upper(), e)
            log.info("[ORCH][%s] Restarting in %.1fs…", name.upper(), restart_delay)
            await asyncio.sleep(restart_delay)


async def watchdog(tasks: dict, interval: float = 10.0):
    """
    Simple watchdog: periodically logs which chains are alive.
    """
    while True:
        await asyncio.sleep(interval)
        statuses = []
        for name, task in tasks.items():
            if task.cancelled():
                state = "CANCELLED"
            elif task.done():
                state = "DONE"
            else:
                state = "RUNNING"
            statuses.append(f"{name}={state}")
        log.info("[ORCH][WATCHDOG] %s", " | ".join(statuses))


async def main():
    # Basic logging setup for orchestrator
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
    )

    log.info("[ORCH] Starting orchestrator with CONFIG_PATH=%s", CONFIG_PATH)
    healthcheck_config()
    cfg = load_config()

    chains = cfg.get("chains", ["tron"])
    log.info("[ORCH] Chains requested: %s", chains)

    tasks = {}

    # Per-chain healthchecks + supervised tasks
    if "tron" in chains and await healthcheck_chain("tron", cfg):
        tasks["tron"] = asyncio.create_task(
            supervised_task("tron", run_tron, cfg), name="tron_supervisor"
        )

    if "eth" in chains and await healthcheck_chain("eth", cfg):
        tasks["eth"] = asyncio.create_task(
            supervised_task("eth", run_eth, cfg), name="eth_supervisor"
        )

    if "btc" in chains and await healthcheck_chain("btc", cfg):
        tasks["btc"] = asyncio.create_task(
            supervised_task("btc", run_btc, cfg), name="btc_supervisor"
        )

    if not tasks:
        log.warning("[ORCH] No chains enabled or all healthchecks failed.")
        print("[ORCH] No chains enabled")
        return

    # Watchdog
    wd = asyncio.create_task(watchdog(tasks), name="orchestrator_watchdog")

    try:
        await asyncio.gather(*tasks.values())
    except asyncio.CancelledError:
        log.info("[ORCH] Orchestrator cancelled, shutting down.")
    finally:
        wd.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await wd


if __name__ == "__main__":
    import contextlib
    asyncio.run(main())
