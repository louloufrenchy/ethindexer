import asyncpg
import asyncio
import os
import yaml
from decimal import Decimal

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\tron_indexer\config\indexer.yaml")

async def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

async def main(address: str):
    cfg = await load_config()
    pg = cfg["database"]["postgres"]
    dsn = f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"

    conn = await asyncpg.connect(dsn)

    rows = await conn.fetch(
        """
        SELECT txid, direction, contract_address, amount_raw, block_number, ts
        FROM address_tx_index
        WHERE address = $1
        ORDER BY block_number DESC
        LIMIT 100
        """,
        address,
    )

    print(f"[ADDRESS] Last {len(rows)} entries for {address}")
    total_in = Decimal(0)
    total_out = Decimal(0)

    for r in rows:
        amt = Decimal(r["amount_raw"])
        if r["direction"] == "in":
            total_in += amt
        else:
            total_out += amt
        print(
            f"{r['block_number']} {r['direction']} {r['amount_raw']} "
            f"{r['contract_address']} {r['txid']}"
        )

    print(f"\n[SUMMARY] total_in={total_in}, total_out={total_out}, net={total_in - total_out}")

    await conn.close()

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("Usage: python tools/check_address_history.py <address>")
    else:
        asyncio.run(main(sys.argv[1]))
