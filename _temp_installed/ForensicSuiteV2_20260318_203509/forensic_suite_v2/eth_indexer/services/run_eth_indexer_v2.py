import asyncio
import logging
import argparse
from pathlib import Path
import yaml
from typing import Any, Dict
from types import SimpleNamespace

from forensic_suite_v2.eth_indexer.services.eth_indexer_service import EthIndexerService
from forensic_suite_v2.core.schema_validator import validate_schema

import sys, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"

logging.basicConfig(
    level=logging.INFO,
    format="%(message)s"
)

def load_config() -> Dict[str, Any]:
    with open(DEFAULT_CONFIG, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

# ---------------------------------------------------------
# REAL async logic lives here
# ---------------------------------------------------------
async def async_main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cfg = load_config()
    eth_cfg = SimpleNamespace(**cfg["eth"])

    eth_cfg.dry_run = args.dry_run
    eth_cfg.dry_run_limit = 20

    await validate_schema(cfg["postgres"])

    indexer = EthIndexerService(eth_cfg)
    await indexer.run()

# ---------------------------------------------------------
# ENTRYPOINT for console script (MUST be sync)
# ---------------------------------------------------------
def main():
    asyncio.run(async_main())

if __name__ == "__main__":
    main()
