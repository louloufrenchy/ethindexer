from __future__ import annotations
import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Iterable
import asyncpg

log = logging.getLogger("tron_db_writer")

class TronDBWriter:
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
        if self.queue.empty(): return
        items = []
        while not self.queue.empty():
            items.append(await self.queue.get())
            self.queue.task_done()

        pool = await self._ensure_pool()
        async with pool.acquire() as conn:
            async with conn.transaction():
                try:
                    if items:
                        first = items[0]
                        b_num = first.get("block_number")
                        b_hash = first.get("block_hash") or first.get("blockID") or first.get("txid")

                        ts_val = first.get("timestamp_ms")
                        if ts_val:
                            ts_naive = datetime.fromtimestamp(ts_val/1000.0, tz=timezone.utc).replace(tzinfo=None)
                        else:
                            ts_naive = datetime.now(timezone.utc).replace(tzinfo=None)

                        if b_num and b_hash:
                            await conn.execute(
                                "INSERT INTO tron_blocks (block_number, block_hash, ts) VALUES ($1, $2, $3) ON CONFLICT (block_number) DO UPDATE SET block_hash=EXCLUDED.block_hash, ts=EXCLUDED.ts",
                                b_num, b_hash, ts_naive
                            )

                        for tx in items:
                            await self._upsert_tron_transaction(conn, tx, ts_naive)
                            await self._insert_trx_transfers(conn, tx) # Native TRX (No TS column)
                            await self._insert_trc20_transfers(conn, tx, ts_naive)
                            await self._insert_address_tx_index(conn, tx, ts_naive)

                    log.info(f"[TRON][DB] Atomic flush successful: {len(items)} txs")
                except Exception as e:
                    log.error(f"[TRON][DB] Atomic flush FAILED: {e}")
                    for item in items: await self.queue.put(item)
                    raise

    async def _upsert_tron_transaction(self, conn, tx, fallback_ts):
        ts_val = tx.get("timestamp_ms")
        ts = datetime.fromtimestamp(ts_val/1000.0, tz=timezone.utc).replace(tzinfo=None) if ts_val else fallback_ts
        await conn.execute(
            "INSERT INTO tron_transactions (tx_hash, block_number, ts, status) VALUES ($1, $2, $3, $4) ON CONFLICT (tx_hash) DO UPDATE SET block_number=EXCLUDED.block_number, ts=EXCLUDED.ts, status=EXCLUDED.status",
            tx["txid"], tx["block_number"], ts, str(tx.get("status"))
        )

    async def _insert_trx_transfers(self, conn, tx):
        """Strict fix: Removed TS column to match native trx_transfers table schema."""
        if tx.get("from_address") and tx.get("to_address") and tx.get("contract_address") == "TRX":
            amount = int(tx["amount_raw"]) if tx.get("amount_raw") else 0
            await conn.execute(
                "INSERT INTO trx_transfers (txid, from_address, to_address, amount, block_number) VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING",
                tx["txid"], tx["from_address"], tx["to_address"], amount, tx["block_number"]
            )

    async def _insert_trc20_transfers(self, conn, tx, fallback_ts):
        for tr in tx.get("trc20_transfers", []):
            ts_ms = tr.get("timestamp_ms") or tx.get("timestamp_ms")
            ts_aware = datetime.fromtimestamp(ts_ms/1000.0, tz=timezone.utc) if ts_ms else fallback_ts.replace(tzinfo=timezone.utc)
            await conn.execute(
                """INSERT INTO trc20_transfers (txid, log_index, contract_address, from_address, to_address, amount_raw, block_number, ts)
                   SELECT $1, $2, $3, $4, $5, $6, $7, $8 WHERE NOT EXISTS (
                       SELECT 1 FROM trc20_transfers WHERE txid=$1 AND log_index=$2 AND contract_address=$3 AND ts=$8
                   )""",
                tr["txid"], tr["log_index"], tr["contract_address"], tr["from_address"], tr["to_address"], str(tr["amount_raw"]), tr["block_number"], ts_aware
            )

    async def _insert_address_tx_index(self, conn, tx, fallback_ts):
        ts_ms = tx.get("timestamp_ms")
        ts_aware = datetime.fromtimestamp(ts_ms/1000.0, tz=timezone.utc) if ts_ms else fallback_ts.replace(tzinfo=timezone.utc)

        entries = []
        if tx.get("from_address"):
            entries.append((tx["from_address"], tx["txid"], "out", str(tx.get("contract_address") or "TRX"), str(tx.get("amount_raw") or 0)))
        if tx.get("to_address"):
            entries.append((tx["to_address"], tx["txid"], "in", str(tx.get("contract_address") or "TRX"), str(tx.get("amount_raw") or 0)))

        for tr in tx.get("trc20_transfers", []):
            entries.append((tr["from_address"], tx["txid"], "out", tr["contract_address"], str(tr["amount_raw"])))
            entries.append((tr["to_address"], tx["txid"], "in", tr["contract_address"], str(tr["amount_raw"])))

        for addr, txid, direction, contract, amount in entries:
            await conn.execute(
                """INSERT INTO address_tx_index (address, txid, direction, contract_address, amount_raw, block_number, ts)
                   SELECT $1, $2, $3, $4, $5, $6, $7 WHERE NOT EXISTS (
                       SELECT 1 FROM address_tx_index WHERE address=$1 AND txid=$2 AND direction=$3 AND ts=$7
                   )""",
                addr, txid, direction, contract, amount, tx["block_number"], ts_aware
            )

    async def rollback(self, height: int) -> None:
        pool = await self._ensure_pool()
        async with pool.acquire() as conn:
            async with conn.transaction():
                for tbl in ["address_tx_index", "trc20_transfers", "trx_transfers", "tron_transactions", "tron_blocks"]:
                    await conn.execute(f"DELETE FROM {tbl} WHERE block_number > $1", int(height))
