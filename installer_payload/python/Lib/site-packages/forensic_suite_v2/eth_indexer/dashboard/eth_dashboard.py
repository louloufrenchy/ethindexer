import asyncio
import asyncpg
import os
import time
from datetime import datetime, timezone
from pathlib import Path
import yaml


# ------------------------------------------------------------
# Resolve CONFIG_PATH deterministically
# ------------------------------------------------------------
# BASE_DIR = forensic_suite_v2/eth_indexer
BASE_DIR = Path(__file__).resolve().parents[1]

DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"

CONFIG_PATH = Path(
    os.environ.get("CONFIG_PATH", str(DEFAULT_CONFIG))
).resolve()


# ------------------------------------------------------------
# Load config lazily (not at import time)
# ------------------------------------------------------------
def load_config():
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(f"Config file not found: {CONFIG_PATH}")

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# ------------------------------------------------------------
# Dashboard logic
# ------------------------------------------------------------
REFRESH = 2.0  # seconds


async def fetch_metrics(conn):
    return await conn.fetchrow("""
        SELECT ts, last_block, chain_head, lag
        FROM indexer_metrics
        WHERE chain = 'eth'
        ORDER BY ts DESC
        LIMIT 1
    """)


async def fetch_block_counts(conn):
    row = await conn.fetchrow("SELECT COUNT(*) AS c FROM eth_blocks")
    tx = await conn.fetchrow("SELECT COUNT(*) AS c FROM eth_transactions")
    logs = await conn.fetchrow("SELECT COUNT(*) AS c FROM eth_logs")
    return row["c"], tx["c"], logs["c"]


def clear():
    os.system("cls" if os.name == "nt" else "clear")


def progress_bar(current, total, width=40):
    if total <= 0:
        return "[no head]"
    pct = current / total
    filled = int(width * pct)
    return "[" + "#" * filled + "-" * (width - filled) + f"] {pct*100:5.1f}%"


async def main():
    cfg = load_config()

    pg = cfg["database"]["postgres"]
    PG_DSN = (
        f"postgres://{pg['user']}:{pg['password']}"
        f"@{pg['host']}:{pg['port']}/{pg['database']}"
    )

    conn = await asyncpg.connect(PG_DSN)
    await conn.execute("SET search_path TO public")

    print("[ETH DASHBOARD] Connected to Postgres")
    time.sleep(1)

    while True:
        metrics = await fetch_metrics(conn)
        blocks, txs, logs = await fetch_block_counts(conn)

        clear()
        print("=== ETH Ingestion Dashboard (updates every 2s) ===")
        print(f"Config: {CONFIG_PATH}")
        print(f"Time:   {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
        print("")

        if metrics:
            last_block = metrics["last_block"]
            head = metrics["chain_head"]
            lag = metrics["lag"]

            print(f"Last Indexed Block: {last_block:,}")
            print(f"Chain Head:         {head:,}")
            print(f"Ingestion Lag:      {lag:,} blocks")
            print("")
            print("Progress:")
            print(progress_bar(last_block, head))
        else:
            print("No ETH metrics yet. Waiting for indexer…")

        print("")
        print("=== Table Counts ===")
        print(f"eth_blocks:       {blocks:,}")
        print(f"eth_transactions: {txs:,}")
        print(f"eth_logs:         {logs:,}")

        print("\n(CTRL+C to exit)")
        await asyncio.sleep(REFRESH)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[ETH DASHBOARD] Exiting…")
