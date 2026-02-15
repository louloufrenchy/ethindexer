import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import aiohttp
import asyncpg

# -------------------------------------------------------------------
# Logging
# -------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [token_daemon] %(levelname)s: %(message)s",
)
log = logging.getLogger("token_daemon")


# -------------------------------------------------------------------
# Token Daemon
# -------------------------------------------------------------------
class TokenDaemon:
    """
    Async TRC20 token metadata refresher.

    Responsibilities:
    - Poll token_registry table for tokens missing metadata
    - Fetch metadata from TRON RPC (name, symbol, decimals)
    - Update Postgres
    - Run forever as a background service
    """

    def __init__(self, config: Dict[str, Any]):
        self.config = config

        pg = config["database"]["postgres"]
        self.pg_dsn = (
            f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"
        )

        tron = config["tron_rpc"]
        self.rpc_url = tron["base_url"].rstrip("/") + "/wallet/getcontract"
        self.poll_interval = config.get("token_daemon", {}).get("poll_interval", 10)

    # -------------------------------------------------------------------
    # RPC Call
    # -------------------------------------------------------------------
    async def fetch_contract(self, session: aiohttp.ClientSession, address: str) -> Optional[Dict[str, Any]]:
        try:
            async with session.post(self.rpc_url, json={"value": address}) as resp:
                resp.raise_for_status()
                return await resp.json()
        except Exception as e:
            log.error(f"RPC error for {address}: {e}")
            return None

    # -------------------------------------------------------------------
    # Metadata Extraction
    # -------------------------------------------------------------------
    @staticmethod
    def extract_metadata(contract: Dict[str, Any]) -> Dict[str, Any]:
        abi = contract.get("abi", {})
        entries = abi.get("entrys", [])

        name = None
        symbol = None
        decimals = None

        for entry in entries:
            if entry.get("name") == "name":
                name = entry.get("outputs", [{}])[0].get("type")
            if entry.get("name") == "symbol":
                symbol = entry.get("outputs", [{}])[0].get("type")
            if entry.get("name") == "decimals":
                decimals = entry.get("outputs", [{}])[0].get("type")

        return {
            "name": name,
            "symbol": symbol,
            "decimals": decimals,
        }

    # -------------------------------------------------------------------
    # DB Operations
    # -------------------------------------------------------------------
    async def get_tokens_to_update(self, conn: asyncpg.Connection) -> list[asyncpg.Record]:
        rows = await conn.fetch(
            """
            SELECT contract_address
            FROM token_registry
            WHERE name IS NULL OR symbol IS NULL OR decimals IS NULL
            ORDER BY updated_at NULLS FIRST
            LIMIT 50
            """
        )
        return rows

    async def update_token(self, conn: asyncpg.Connection, address: str, meta: Dict[str, Any]):
        await conn.execute(
            """
            UPDATE token_registry
            SET name = $2,
                symbol = $3,
                decimals = $4,
                updated_at = $5
            WHERE contract_address = $1
            """,
            address,
            meta["name"],
            meta["symbol"],
            meta["decimals"],
            datetime.now(timezone.utc),
        )

    # -------------------------------------------------------------------
    # Main Loop
    # -------------------------------------------------------------------
    async def run(self):
        log.info("Starting TRON token daemon…")

        conn = await asyncpg.connect(self.pg_dsn)
        session = aiohttp.ClientSession()

        try:
            while True:
                tokens = await self.get_tokens_to_update(conn)

                if not tokens:
                    await asyncio.sleep(self.poll_interval)
                    continue

                log.info(f"Found {len(tokens)} tokens needing metadata")

                for row in tokens:
                    address = row["contract_address"]
                    contract = await self.fetch_contract(session, address)

                    if not contract:
                        continue

                    meta = self.extract_metadata(contract)
                    await self.update_token(conn, address, meta)

                    log.info(f"Updated metadata for {address}: {meta}")

                await asyncio.sleep(self.poll_interval)

        except asyncio.CancelledError:
            log.info("Token daemon shutting down…")
        finally:
            await session.close()
            await conn.close()


# -------------------------------------------------------------------
# Entrypoint
# -------------------------------------------------------------------
async def main():
    import yaml
    from pathlib import Path

    base = Path(__file__).resolve().parents[2]
    cfg_path = base / "config" / "indexer.yaml"

    with open(cfg_path, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    daemon = TokenDaemon(cfg)
    await daemon.run()


if __name__ == "__main__":
    asyncio.run(main())
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
