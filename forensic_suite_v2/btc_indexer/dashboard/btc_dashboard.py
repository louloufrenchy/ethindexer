import asyncio
import asyncpg
import os
import time
from datetime import datetime, timezone
from forensic_suite_v2.btc_indexer.services.run_btc_indexer_v2 import main as run_btc
from forensic_suite_v2.eth_indexer.services.run_eth_indexer_v2 import main as run_eth
from forensic_suite_v2.tron_indexer.services.run_tron_indexer_v2 import main as run_tron

CONFIG_PATH = os.environ.get("CONFIG_PATH", "C:/forensic_suite_v2/btc_indexer/config/indexer.yaml")

import yaml
with open(CONFIG_PATH, "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

pg = cfg["database"]["postgres"]
PG_DSN = f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"

REFRESH = 2.0  # seconds


async def fetch_metrics(conn):
    row = await conn.fetchrow("""
        SELECT ts, last_block, chain_head, lag
        FROM indexer_metrics
        WHERE chain = 'btc'
        ORDER BY ts DESC
        LIMIT 1
    """)
    return row


async def fetch_block_counts(conn):
    row = await conn.fetchrow("SELECT COUNT(*) AS c FROM btc_blocks")
    tx = await conn.fetchrow("SELECT COUNT(*) AS c FROM btc_transactions")
    utxo = await conn.fetchrow("SELECT COUNT(*) AS c FROM btc_utxos")
    return row["c"], tx["c"], utxo["c"]


def clear():
    os.system("cls" if os.name == "nt" else "clear")


def progress_bar(current, total, width=40):
    if total <= 0:
        return "[no head]"
    pct = current / total
    filled = int(width * pct)
    return "[" + "#" * filled + "-" * (width - filled) + f"] {pct*100:5.1f}%"


async def main():
    conn = await asyncpg.connect(PG_DSN)
    await conn.execute("SET search_path TO public")

    print("[BTC DASHBOARD] Connected to Postgres")
    time.sleep(1)

    while True:
        metrics = await fetch_metrics(conn)
        blocks, txs, utxos = await fetch_block_counts(conn)

        clear()
        print("=== BTC Ingestion Dashboard (updates every 2s) ===")
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
            print("No BTC metrics yet. Waiting for indexer…")

        print("")
        print("=== Table Counts ===")
        print(f"btc_blocks:       {blocks:,}")
        print(f"btc_transactions: {txs:,}")
        print(f"btc_utxos:        {utxos:,}")

        print("\n(CTRL+C to exit)")
        await asyncio.sleep(REFRESH)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[BTC DASHBOARD] Exiting…")
