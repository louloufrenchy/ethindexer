import asyncio
import os
import yaml
import traceback

# from services.run_indexer import TronQuickNodeIndexer
from services.run_tron_indexer_v2 import TronQuickNodeIndexerV2
#from services.run_eth_indexer import EthIndexer
from services.run_eth_indexer_v2 import EthIndexerV2
#from services.run_btc_indexer import BtcIndexer
from services.run_btc_indexer_v2 import BtcIndexerV2

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\tron_indexer\config\indexer.yaml")


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


async def run_tron(cfg):
    try:
        indexer = TronQuickNodeIndexerV2(cfg)
        await indexer.run()
    except Exception as e:
        print(f"[ORCH][TRON] Fatal error: {e}")


async def run_eth(cfg):
    try:
        indexer = EthIndexerV2(cfg)
        await indexer.run()
    except Exception as e:
        print(f"[ORCH][ETH] Fatal error: {e}")

async def run_btc(cfg):
    try:
        indexer = BtcIndexerV2(cfg)
        await indexer.run()
    except Exception:
        print("[ORCH][BTC] Fatal error, full traceback:")
        traceback.print_exc()

async def main():
    cfg = load_config()
    chains = cfg.get("chains", ["tron"])
    tasks = []

    if "tron" in chains:
        tasks.append(asyncio.create_task(run_tron(cfg)))
    if "eth" in chains:
        tasks.append(asyncio.create_task(run_eth(cfg)))
    if "btc" in chains:
        tasks.append(asyncio.create_task(run_btc(cfg)))

    if not tasks:
        print("[ORCH] No chains enabled")
        return

    await asyncio.gather(*tasks)


if __name__ == "__main__":
    asyncio.run(main())
