import asyncio
import logging
import argparse
import os
import re
import sys
import traceback
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Dict

import yaml

from forensic_suite_v2.eth_indexer.services.eth_indexer_service import EthIndexerService
from forensic_suite_v2.core.schema_validator import validate_schema

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("eth_indexer")

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
                raise RuntimeError(f"Required environment variable not set: {env_name}")
            return env_value
    return value


def load_config() -> Dict[str, Any]:
    with open(DEFAULT_CONFIG, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f)

    resolved: Dict[str, Any] = {}
    resolved["postgres"] = _resolve_env_placeholders(raw["postgres"])

    if "logging" in raw:
        resolved["logging"] = _resolve_env_placeholders(raw["logging"])

    for chain in ["eth", "btc", "tron"]:
        if chain in raw:
            if bool(raw[chain].get("enabled", False)):
                resolved[chain] = _resolve_env_placeholders(raw[chain])
            else:
                resolved[chain] = raw[chain]

    for k, v in raw.items():
        if k not in resolved:
            resolved[k] = v

    return resolved


def build_runtime_config(cfg: Dict[str, Any], chain_name: str, args: argparse.Namespace) -> SimpleNamespace:
    chain_cfg = SimpleNamespace(**cfg[chain_name])
    chain_cfg.postgres = SimpleNamespace(**cfg["postgres"])

    if "logging" in cfg:
        chain_cfg.logging = SimpleNamespace(**cfg["logging"])

    chain_cfg.chain = chain_name
    chain_cfg.dry_run = args.dry_run
    chain_cfg.dry_run_limit = 20
    return chain_cfg


def log_runtime_context(cfg: Dict[str, Any]) -> None:
    eth_cfg = cfg["eth"]
    logger.info(f"[ETH] DEFAULT_CONFIG={DEFAULT_CONFIG}")
    logger.info(f"[ETH] QUICKNODE_ETH_HTTP present={os.getenv('QUICKNODE_ETH_HTTP') is not None}")
    logger.info(f"[ETH] QUICKNODE_ETH_WSS present={os.getenv('QUICKNODE_ETH_WSS') is not None}")
    logger.info(f"[ETH] http_endpoint={eth_cfg.get('http_endpoint')}")
    logger.info(f"[ETH] wss_endpoint={eth_cfg.get('wss_endpoint')}")


async def async_main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cfg = load_config()
    log_runtime_context(cfg)

    await validate_schema(cfg["postgres"])

    eth_cfg = build_runtime_config(cfg, "eth", args)
    indexer = EthIndexerService(eth_cfg)
    await indexer.run()


def main() -> None:
    try:
        asyncio.run(async_main())
    except Exception as exc:
        logger.error(f"[ETH] FATAL: {exc}")
        logger.error(traceback.format_exc())
        raise


if __name__ == "__main__":
    main()
