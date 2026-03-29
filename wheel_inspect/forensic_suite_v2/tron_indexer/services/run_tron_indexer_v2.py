import asyncio
import logging
import argparse
from pathlib import Path
import yaml
from typing import Any, Dict
from types import SimpleNamespace
import os
import re

from forensic_suite_v2.tron_indexer.services.tron_indexer_service import TronIndexerService
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
        m = ENV_PATTERN.match(value.strip())
        if m:
            env_name = m.group(1)
            env_value = os.getenv(env_name)
            if env_value is None:
                raise RuntimeError(f"Missing env var: {env_name}")
            return env_value

    return value

def load_config() -> Dict[str, Any]:
    with open(DEFAULT_CONFIG, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f)
    return _resolve_env_placeholders(raw)

async def async_main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cfg = load_config()
    tron_cfg = SimpleNamespace(**cfg["tron"])

    tron_cfg.dry_run = args.dry_run
    tron_cfg.dry_run_limit = 20

    await validate_schema(cfg["postgres"])

    indexer = TronIndexerService(tron_cfg)
    await indexer.run()

def main():
    asyncio.run(async_main())

if __name__ == "__main__":
    main()
