import asyncio
import logging
import argparse
import os
import re
from pathlib import Path
import yaml
from typing import Any, Dict
from types import SimpleNamespace

from forensic_suite_v2.eth_indexer.services.eth_indexer_service import EthIndexerService
from forensic_suite_v2.core.schema_validator import validate_schema

import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"

logging.basicConfig(
    level=logging.INFO,
    format="%(message)s"
)

ENV_PATTERN = re.compile(r'^\$\{([A-Za-z][A-Za-z0-9_]*)\}$')


def _resolve_env_placeholders(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: _resolve_env_placeholders(v) for k, v in value.items()}

    if isinstance(value, list):
        return [_resolve_env_placeholders(v) for v in value]

    if isinstance(value, str):
        match = ENV_PATTERN.match(value.strip())
        if match:
            env_name = match.group(1)
            env_value = os.getenv(env_name)
            if env_value is None:
                raise RuntimeError(f"Required environment variable not set: {env_name}")
            return env_value

    return value


def load_config() -> Dict[str, Any]:
    with open(DEFAULT_CONFIG, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f)

    return _resolve_env_placeholders(raw)


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
def main() -> None:
    asyncio.run(async_main())


if __name__ == "__main__":
    main()
