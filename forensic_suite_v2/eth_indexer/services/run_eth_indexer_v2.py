import asyncio
from pathlib import Path
import yaml
from typing import Any, Dict

from forensic_suite_v2.eth_indexer.services.eth_indexer_service import EthIndexerService


BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"


def load_config() -> Dict[str, Any]:
    with open(DEFAULT_CONFIG, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


async def main() -> None:
    cfg = load_config()
    indexer = EthIndexerService(cfg)
    await indexer.run()


if __name__ == "__main__":
    asyncio.run(main()