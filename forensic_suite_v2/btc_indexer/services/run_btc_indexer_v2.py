import asyncio
<<<<<<< HEAD
from pathlib import Path
import yaml
from typing import Any, Dict

from forensic_suite_v2.btc_indexer.services.btc_indexer_service import BtcIndexerService

=======
>>>>>>> master
import logging
import argparse
from pathlib import Path
import yaml
from typing import Any, Dict
from types import SimpleNamespace

from forensic_suite_v2.btc_indexer.services.btc_indexer_service import BtcIndexerService
from forensic_suite_v2.core.schema_validator import validate_schema

<<<<<<< HEAD
# import debugpy
# debugpy.listen(("0.0.0.0", 5678))
# print("Waiting for debugger attach on port 5678...")
# debugpy.wait_for_client()
=======
import sys, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
>>>>>>> master

BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"

logging.basicConfig(
    level=logging.INFO,
    format="%(message)s"
)

def load_config() -> Dict[str, Any]:
    with open(DEFAULT_CONFIG, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

<<<<<<< HEAD

async def main() -> None:
    cfg = load_config()
    indexer = BtcIndexerService(cfg)
=======
# ---------------------------------------------------------
# REAL async logic lives here
# ---------------------------------------------------------
async def async_main() -> None:
>>>>>>> master
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cfg = load_config()
    btc_cfg = SimpleNamespace(**cfg["btc"])

<<<<<<< HEAD
    # CLI controls dry-run
=======
>>>>>>> master
    btc_cfg.dry_run = args.dry_run
    btc_cfg.dry_run_limit = 20

    await validate_schema(cfg["postgres"])

    indexer = BtcIndexerService(btc_cfg)
    await indexer.run()

<<<<<<< HEAD

if __name__ == "__main__":
    asyncio.run(main())
    asyncio.run(main())
=======
# ---------------------------------------------------------
# ENTRYPOINT for console script (MUST be sync)
# ---------------------------------------------------------
def main():
    asyncio.run(async_main())

if __name__ == "__main__":
    main()
>>>>>>> master
