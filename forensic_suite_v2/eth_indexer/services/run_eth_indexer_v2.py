import asyncio
from pathlib import Path
import yaml
from typing import Any, Dict

from forensic_suite_v2.eth_indexer.services.eth_indexer_service import EthIndexerService

import logging
import argparse
from pathlib import Path
import yaml
from typing import Any, Dict
from types import SimpleNamespace

from forensic_suite_v2.eth_indexer.services.eth_indexer_service import EthIndexerService
from forensic_suite_v2.core.schema_validator import validate_schema

import debugpy
debugpy.listen(("0.0.0.0", 5678))
print("Waiting for debugger attach on port 5678...")
debugpy.wait_for_client()

BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"

logging.basicConfig(
    level=logging.INFO,
    format="%(message)s"
)

def load_config() -> Dict[str, Any]:
    with open(DEFAULT_CONFIG, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


async def main() -> None:
    cfg = load_config()
    indexer = EthIndexerService(cfg)
    await indexer.run()


if __name__ == "__main__":
    asyncio.run(main()
async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cfg = load_config()
    eth_cfg = SimpleNamespace(**cfg["eth"])

    # CLI controls dry-run
    eth_cfg.dry_run = args.dry_run
    eth_cfg.dry_run_limit = 20

    await validate_schema(cfg["postgres"])

    indexer = EthIndexerService(eth_cfg)
    await indexer.run()

if __name__ == "__main__":
    asyncio.run(main())
