import asyncpg
import asyncio
import os
import yaml
import aiohttp

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\tron_indexer\config\indexer.yaml")

async def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

async def get_last_checkpoint(conn):
    row = await conn.fetchrow("SELECT last_block FROM index_checkpoint WHERE id = 1")
    return row["last_block"] if row else 0

async def get_head(cfg):
    rpc_base = cfg["tron_rpc"]["base_url"].rstrip("/")
    wallet_url = rpc_base + "/wallet/getnowblock"
    timeout = cfg["tron_rpc"]["timeout"]

    async with aiohttp.ClientSession() as session:
        async with session.post(wallet_url, json={}) as resp:
            resp.raise_for_status()
            data = await resp.json()
    header = data.get("block_header", {}).get("raw_data", {})
    return int(header.get("number", 0))

async def main():
    cfg = await load_config()
    pg = cfg["database"]["postgres"]
    dsn = f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"

    conn = await asyncpg.connect(dsn)
    last = await get_last_checkpoint(conn)
    await conn.close()

    head = await get_head(cfg)
    lag = head - last

    print(f"last_indexed: {last}")
    print(f"chain_head:   {head}")
    print(f"lag:          {lag} blocks")

if __name__ == "__main__":
    asyncio.run(main())
