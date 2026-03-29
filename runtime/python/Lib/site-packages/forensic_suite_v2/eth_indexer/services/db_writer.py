from __future__ import annotations
import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Iterable
import asyncpg

log = logging.getLogger("eth_db_writer")

class EthDBWriter:
    def __init__(self, config: Any):
        self.config = config
        self.queue: asyncio.Queue[dict] = asyncio.Queue()
        self._pool: asyncpg.Pool | None = None

    async def _ensure_pool(self) -> asyncpg.Pool:
        if self._pool is None:
            pg = self.config.postgres
            dsn = f"postgresql://{pg.user}:{pg.password}@{pg.host}:{pg.port}/{pg.database}"
            self._pool = await asyncpg.create_pool(dsn=dsn, min_size=1, max_size=4)
        return self._pool

    async def flush(self) -> None:
        if self.queue.empty():
            return

        items: list[dict] = []
        while not self.queue.empty():
            items.append(await self.queue.get())
            self.queue.task_done()

        pool = await self._ensure_pool()
        async with pool.acquire() as conn:
            async with conn.transaction():
                try:
                    if items:
                        first = items[0]
                        # Create fallback naive timestamp from block context or current time
                        ts_val = first.get("timestamp_ms")
                        if ts_val:
                            ts_naive = datetime.fromtimestamp(ts_val / 1000.0, tz=timezone.utc).replace(tzinfo=None)
                        else:
                            ts_naive = datetime.now(timezone.utc).replace(tzinfo=None)
                            log.warning(f"[ETH] Using current time fallback for block {first.get('block_number')}")

                        await conn.execute(
                            """INSERT INTO eth_blocks (block_number, block_hash, ts)
                               VALUES ($1, $2, $3)
                               ON CONFLICT (block_number) DO UPDATE
                               SET block_hash = EXCLUDED.block_hash, ts = EXCLUDED.ts""",
                            first["block_number"], first["block_hash"], ts_naive
                        )

                        # Process items using the block's ts_naive as fallback for transactions
                        for tx in items:
                            await self._upsert_eth_transaction(conn, tx, ts_naive)
                            await self._insert_erc20_transfers(conn, tx, ts_naive)
                            await self._insert_address_tx_index(conn, tx, ts_naive)

                    log.info(f"[ETH][DB] Atomic flush successful: {len(items)} txs")
                except Exception as e:
                    log.error(f"[ETH][DB] Atomic flush FAILED: {e}")
                    for item in items:
                        await self.queue.put(item)
                    raise

    async def _upsert_eth_transaction(self, conn, tx, fallback_ts):
        ts_val = tx.get("timestamp_ms")
        ts = datetime.fromtimestamp(ts_val / 1000.0, tz=timezone.utc).replace(tzinfo=None) if ts_val else fallback_ts
        await conn.execute(
            """INSERT INTO eth_transactions (tx_hash, block_number, ts, status)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (tx_hash) DO UPDATE
               SET block_number = EXCLUDED.block_number, ts = EXCLUDED.ts, status = EXCLUDED.status""",
            tx["txid"], tx["block_number"], ts, 1 if tx.get("status") == "success" else 0
        )

    async def _insert_erc20_transfers(self, conn, tx, fallback_ts):
        for tr in tx.get("erc20_transfers", []):
            ts_ms = tr.get("timestamp_ms") or tx.get("timestamp_ms")
            ts_aware = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc) if ts_ms else fallback_ts.replace(tzinfo=timezone.utc)
            await conn.execute(
                """INSERT INTO erc20_transfers (tx_hash, log_index, contract_address, from_address, to_address, amount_raw, block_number, ts)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT DO NOTHING""",
                tr["txid"], tr["log_index"], tr["contract_address"], tr["from_address"], tr["to_address"], str(tr["amount_raw"]), tr["block_number"], ts_aware
            )

    async def _insert_address_tx_index(self, conn, tx, fallback_ts):
        ts_ms = tx.get("timestamp_ms")
        ts_aware = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc) if ts_ms else fallback_ts.replace(tzinfo=timezone.utc)
        for entry in self._extract_address_index_rows(tx):
            await conn.execute(
                """INSERT INTO address_tx_index (address, txid, direction, contract_address, amount_raw, block_number, ts)
                   SELECT $1, $2, $3, $4, $5, $6, $7 WHERE NOT EXISTS (
                       SELECT 1 FROM address_tx_index WHERE address=$1 AND txid=$2 AND direction=$3 AND contract_address=$4 AND ts=$7
                   )""",
                entry["address"], entry["txid"], entry["direction"], entry["contract_address"], str(entry["amount_raw"]), entry["block_number"], ts_aware
            )

    def _extract_address_index_rows(self, tx: dict) -> Iterable[dict]:
        txid, b_num = tx.get("txid"), tx.get("block_number")
        for tr in tx.get("erc20_transfers", []):
            for side in ["from_address", "to_address"]:
                if tr.get(side):
                    yield {
                        "address": tr[side], "txid": txid,
                        "direction": "out" if side == "from_address" else "in",
                        "contract_address": tr["contract_address"],
                        "amount_raw": tr["amount_raw"], "block_number": b_num
                    }

    async def rollback(self, height: int) -> None:
        pool = await self._ensure_pool()
        async with pool.acquire() as conn:
            async with conn.transaction():
                for tbl in ["address_tx_index", "erc20_transfers", "eth_transactions", "eth_blocks"]:
                    await conn.execute(f"DELETE FROM {tbl} WHERE block_number > $1", int(height))
