import asyncio
import asyncpg
import os
import time
from datetime import datetime, timezone
from pathlib import Path
import yaml


# ------------------------------------------------------------
# Resolve a shared CONFIG_PATH deterministically
# Assumes a top-level config/indexer.yaml for multi-chain,
# or falls back to BTC indexer config if you prefer.
# ------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parents[1]

DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"

CONFIG_PATH = Path(
    os.environ.get("CONFIG_PATH", str(DEFAULT_CONFIG))
).resolve()


def load_config():
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(f"Config file not found: {CONFIG_PATH}")

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


REFRESH = 2.0  # seconds
CHAINS = ["btc", "eth", "tron"]


async def fetch_metrics(conn, chain: str):
    return await conn.fetchrow("""
        SELECT ts, last_block, chain_head, lag
        FROM indexer_metrics
        WHERE chain = $1
        ORDER BY ts DESC
        LIMIT 1
    """, chain)


async def fetch_counts_for_chain(conn, chain: str):
    if chain == "btc":
        blocks = await conn.fetchrow("SELECT COUNT(*) AS c FROM btc_blocks")
        txs = await conn.fetchrow("SELECT COUNT(*) AS c FROM btc_transactions")
        extra = await conn.fetchrow("SELECT COUNT(*) AS c FROM btc_utxos")
        label_extra = "btc_utxos"
    elif chain == "eth":
        blocks = await conn.fetchrow("SELECT COUNT(*) AS c FROM eth_blocks")
        txs = await conn.fetchrow("SELECT COUNT(*) AS c FROM eth_transactions")
        extra = await conn.fetchrow("SELECT COUNT(*) AS c FROM eth_logs")
        label_extra = "eth_logs"
    elif chain == "tron":
        blocks = await conn.fetchrow("SELECT COUNT(*) AS c FROM tron_blocks")
        txs = await conn.fetchrow("SELECT COUNT(*) AS c FROM tron_transactions")
        extra = await conn.fetchrow("SELECT COUNT(*) AS c FROM tron_trc20_transfers")
        label_extra = "tron_trc20_transfers"
    else:
        return (0, 0, 0, "extra")

    return blocks["c"], txs["c"], extra["c"], label_extra


def clear():
    os.system("cls" if os.name == "nt" else "clear")


def progress_bar(current, total, width=30):
    if total is None or total <= 0:
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

    print("[MULTI-CHAIN DASHBOARD] Connected to Postgres")
    time.sleep(1)

    while True:
        clear()
        print("=== Multi-Chain Ingestion Dashboard (updates every 2s) ===")
        print(f"Config: {CONFIG_PATH}")
        print(f"Time:   {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
        print("")

        # Fetch metrics and counts in parallel per chain
        metrics_tasks = [fetch_metrics(conn, c) for c in CHAINS]
        counts_tasks = [fetch_counts_for_chain(conn, c) for c in CHAINS]

        metrics_results = await asyncio.gather(*metrics_tasks, return_exceptions=True)
        counts_results = await asyncio.gather(*counts_tasks, return_exceptions=True)

        for idx, chain in enumerate(CHAINS):
            metrics = metrics_results[idx]
            counts = counts_results[idx]

            print(f"--- {chain.upper()} ---")

            if isinstance(metrics, Exception):
                print(f"[ERROR] Metrics error: {metrics}")
                print("")
                continue

            if isinstance(counts, Exception):
                print(f"[ERROR] Counts error: {counts}")
                print("")
                continue

            blocks, txs, extra, extra_label = counts

            if metrics:
                last_block = metrics["last_block"]
                head = metrics["chain_head"]
                lag = metrics["lag"]

                print(f"Last Indexed Block: {last_block:,}")
                print(f"Chain Head:         {head:,}")
                print(f"Ingestion Lag:      {lag:,} blocks")
                print(f"Progress:           {progress_bar(last_block, head)}")
            else:
                print("No metrics yet. Waiting for indexer…")

            print("Table Counts:")
            print(f"  {chain}_blocks:    {blocks:,}")
            print(f"  {chain}_txs:       {txs:,}")
            print(f"  {extra_label}:     {extra:,}")
            print("")

        print("\n(CTRL+C to exit)")
        await asyncio.sleep(REFRESH)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[MULTI-CHAIN DASHBOARD] Exiting…")
