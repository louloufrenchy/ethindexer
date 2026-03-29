import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import aiohttp
import asyncpg

import sys, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

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
