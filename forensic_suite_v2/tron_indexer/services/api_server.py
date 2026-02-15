import os
import yaml
import asyncpg
import aiohttp
from pathlib import Path
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = BASE_DIR / "config" / "indexer.yaml"
CONFIG_PATH = os.environ.get("CONFIG_PATH", str(DEFAULT_CONFIG))
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\tron_indexer\config\indexer.yaml")

app = FastAPI()
db_pool = None
config = None


class TronTxResponse(BaseModel):
    txid: str
    block_number: int
    timestamp: int | None
    status: str | None


class EthTxResponse(BaseModel):
    tx_hash: str
    block_number: int
    timestamp: int | None
    status: str | None


async def load_config():
    global config
    if config is None:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            config = yaml.safe_load(f)
    return config


@app.on_event("startup")
async def startup():
    global db_pool
    cfg = await load_config()
    pg = cfg["database"]["postgres"]
    dsn = f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"
    db_pool = await asyncpg.create_pool(dsn, min_size=1, max_size=10)


@app.on_event("shutdown")
async def shutdown():
    global db_pool
    if db_pool:
        await db_pool.close()


@app.get("/status")
async def status():
    cfg = await load_config()
    async with db_pool.acquire() as conn:
        tron_row = await conn.fetchrow(
            "SELECT last_block FROM index_checkpoint WHERE id = 1"
        )
        eth_row = await conn.fetchrow(
            "SELECT last_block FROM index_checkpoint WHERE id = 2"
        )
        btc_row = await conn.fetchrow(
            "SELECT last_block FROM index_checkpoint WHERE id = 3"
        )

    tron_last = tron_row["last_block"] if tron_row else 0
    eth_last = eth_row["last_block"] if eth_row else 0
    btc_last = btc_row["last_block"] if btc_row else 0

    # TRON head
    tron_rpc = cfg["tron_rpc"]["base_url"].rstrip("/") + "/wallet/getnowblock"
    async with aiohttp.ClientSession() as session:
        async with session.post(tron_rpc, json={}) as resp:
            resp.raise_for_status()
            data = await resp.json()
    header = data.get("block_header", {}).get("raw_data", {})
    tron_head = int(header.get("number", 0))

    # ETH head
    eth_rpc = cfg["eth_rpc"]["base_url"].rstrip("/")
    async with aiohttp.ClientSession() as session:
        async with session.post(
            eth_rpc,
            json={"jsonrpc": "2.0", "id": 1, "method": "eth_blockNumber", "params": []},
        ) as resp:
            resp.raise_for_status()
            data = await resp.json()
    eth_head = int(data.get("result", "0x0"), 16)

    # BTC head
    btc = cfg["btc_rpc"]
    from base64 import b64encode
    auth_str = f"{btc['username']}:{btc['password']}".encode("utf-8")
    auth_header = "Basic " + b64encode(auth_str).decode("ascii")
    async with aiohttp.ClientSession() as session:
        async with session.post(
            btc["base_url"],
            json={"jsonrpc": "1.0", "id": "btc", "method": "getblockcount", "params": []},
            headers={"Authorization": auth_header},
        ) as resp:
            resp.raise_for_status()
            data = await resp.json()
    btc_head = int(data.get("result", 0))

    return {
        "tron": {
            "last_indexed": tron_last,
            "chain_head": tron_head,
            "lag": tron_head - tron_last,
        },
        "eth": {
            "last_indexed": eth_last,
            "chain_head": eth_head,
            "lag": eth_head - eth_last,
        },
        "btc": {
            "last_indexed": btc_last,
            "chain_head": btc_head,
            "lag": btc_head - btc_last,
        },
    }


@app.get("/metrics")
async def metrics(chain: str | None = None, limit: int = 50):
    query = """
        SELECT ts, chain, last_block, chain_head, lag
        FROM indexer_metrics
    """
    params = []
    if chain:
        query += " WHERE chain = $1"
        params.append(chain)
    query += " ORDER BY ts DESC LIMIT $2"
    params.append(limit)

    async with db_pool.acquire() as conn:
        rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]


@app.get("/tron/tx/{txid}", response_model=TronTxResponse)
async def get_tron_tx(txid: str):
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT txid, block_number, timestamp, status
            FROM transactions
            WHERE txid = $1
            """,
            txid,
        )
    if not row:
        raise HTTPException(status_code=404, detail="TRON transaction not found")
    return TronTxResponse(
        txid=row["txid"],
        block_number=row["block_number"],
        timestamp=row["timestamp"],
        status=row["status"],
    )


@app.get("/tron/address/{address}/transfers")
async def tron_address_transfers(address: str, limit: int = 100):
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT txid, direction, contract_address, amount_raw, block_number, ts
            FROM address_tx_index
            WHERE address = $1
            ORDER BY block_number DESC
            LIMIT $2
            """,
            address,
            limit,
        )
    return [dict(r) for r in rows]


@app.get("/eth/tx/{tx_hash}", response_model=EthTxResponse)
async def get_eth_tx(tx_hash: str):
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT tx_hash, block_number, timestamp, status
            FROM eth_transactions
            WHERE tx_hash = $1
            """,
            tx_hash,
        )
    if not row:
        raise HTTPException(status_code=404, detail="ETH transaction not found")
    return EthTxResponse(
        tx_hash=row["tx_hash"],
        block_number=row["block_number"],
        timestamp=row["timestamp"],
        status=row["status"],
    )


@app.get("/eth/address/{address}/transfers")
async def eth_address_transfers(address: str, limit: int = 100):
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT tx_hash, direction, contract_address, amount_raw, block_number, ts
            FROM eth_address_index
            WHERE address = $1
            ORDER BY block_number DESC
            LIMIT $2
            """,
            address,
            limit,
        )
    return [dict(r) for r in rows]


@app.get("/btc/address/{address}/utxos")
async def btc_address_utxos(address: str, include_spent: bool = False):
    async with db_pool.acquire() as conn:
        if include_spent:
            rows = await conn.fetch(
                """
                SELECT txid, vout, amount_sats, spent, spent_by_txid
                FROM btc_utxos
                WHERE address = $1
                ORDER BY id DESC
                """,
                address,
            )
        else:
            rows = await conn.fetch(
                """
                SELECT txid, vout, amount_sats, spent, spent_by_txid
                FROM btc_utxos
                WHERE address = $1 AND spent = FALSE
                ORDER BY id DESC
                """,
                address,
            )
    return [dict(r) for r in rows]
