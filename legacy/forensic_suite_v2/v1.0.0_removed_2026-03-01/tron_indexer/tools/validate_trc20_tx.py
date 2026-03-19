import asyncpg
import aiohttp
import asyncio
import os
import yaml

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\tron_indexer\config\indexer.yaml")

async def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

async def fetch_db_transfer(conn, txid):
    row = await conn.fetchrow(
        """
        SELECT txid, contract_address, from_address, to_address, amount_raw, block_number
        FROM trc20_transfers
        WHERE txid = $1
        """,
        txid,
    )
    return row

async def main(txid: str):
    cfg = await load_config()
    pg = cfg["database"]["postgres"]
    dsn = f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"

    conn = await asyncpg.connect(dsn)
    row = await fetch_db_transfer(conn, txid)
    await conn.close()

    if not row:
        print(f"[VALIDATE] No TRC20 transfer found in DB for {txid}")
        return

    print("[DB] TRC20 transfer:")
    print(dict(row))
    print("\nNow cross-check this against TronScan for the same txid.")

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("Usage: python tools/validate_trc20_tx.py <txid>")
    else:
        asyncio.run(main(sys.argv[1]))
