import asyncpg
import logging
import yaml
from pathlib import Path

INSTALL_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = INSTALL_ROOT / "config" / "indexer.yaml"

def load_config():
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(f"Config file not found: {CONFIG_PATH}")
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

async def get_db_pool(cfg: dict):
    """
    Create a PostgreSQL connection pool using unified config.
    """
    db_cfg = cfg.get("database", {})
    return await asyncpg.create_pool(
        host=db_cfg.get("host", "localhost"),
        port=db_cfg.get("port", 5432),
        user=db_cfg.get("user", "postgres"),
        password=db_cfg.get("password", ""),
        database=db_cfg.get("dbname", "forensic"),
        min_size=1,
        max_size=5,
    )

async def fetch_row(pool, query: str, *args):
    try:
        async with pool.acquire() as conn:
            return await conn.fetchrow(query, *args)
    except Exception as exc:
        logging.exception(f"DB fetch_row failed: {exc}")
        raise

async def fetch(pool, query: str, *args):
    try:
        async with pool.acquire() as conn:
            return await conn.fetch(query, *args)
    except Exception as exc:
        logging.exception(f"DB fetch failed: {exc}")
        raise
