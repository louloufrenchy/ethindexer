import asyncio
import os
import yaml
import aiohttp
import asyncpg

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\tron_indexer\config\indexer.yaml")

def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

async def tron_trigger_smart_contract(session, rpc_wallet, contract_hex, function_sig):
    payload = {
        "contract_address": contract_hex,
        "function_selector": function_sig,
        "owner_address": "",
        "parameter": "",
    }
    async with session.post(f"{rpc_wallet}/triggersmartcontract", json=payload, timeout=10) as resp:
        resp.raise_for_status()
        return await resp.json()

def decode_string(result):
    try:
        data = result["constant_result"][0]
        bytes_data = bytes.fromhex(data)
        return bytes_data.decode(errors="ignore").strip("\x00")
    except Exception:
        return None

def decode_uint(result):
    try:
        data = result["constant_result"][0]
        return int(data, 16)
    except Exception:
        return None

async def refresh_tokens(config):
    rpc_base = config["tron_rpc"]["base_url"].rstrip("/")
    rpc_wallet = rpc_base + "/wallet"

    pg = config["database"]["postgres"]
    pg_dsn = f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"

    conn = await asyncpg.connect(pg_dsn)

    rows = await conn.fetch("""
        SELECT DISTINCT contract_address
        FROM trc20_transfers
        WHERE contract_address NOT IN (
            SELECT contract_address FROM token_registry
        )
    """)

    if not rows:
        await conn.close()
        return

    async with aiohttp.ClientSession() as session:
        for row in rows:
            contract = row["contract_address"]

            sym_res = await tron_trigger_smart_contract(session, rpc_wallet, contract, "symbol()")
            name_res = await tron_trigger_smart_contract(session, rpc_wallet, contract, "name()")
            dec_res = await tron_trigger_smart_contract(session, rpc_wallet, contract, "decimals()")

            symbol = decode_string(sym_res) or "UNKNOWN"
            name = decode_string(name_res) or "UNKNOWN"
            decimals = decode_uint(dec_res) or 6

            await conn.execute(
                """
                INSERT INTO token_registry (contract_address, symbol, name, decimals)
                VALUES ($1,$2,$3,$4)
                ON CONFLICT (contract_address) DO NOTHING
                """,
                contract,
                symbol,
                name,
                decimals,
            )

    await conn.close()

async def main():
    config = load_config()
    while True:
        await refresh_tokens(config)
        await asyncio.sleep(3600)

if __name__ == "__main__":
    asyncio.run(main())
