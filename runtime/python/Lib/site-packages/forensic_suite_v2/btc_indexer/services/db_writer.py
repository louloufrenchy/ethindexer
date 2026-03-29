from __future__ import annotations
import asyncio
import logging
from datetime import datetime, timezone
from typing import Any
import asyncpg

log = logging.getLogger("btc_db_writer")

class BtcDBWriter:
    def __init__(self, config: Any):
        self.config = config
        self.queue: asyncio.Queue[dict] = asyncio.Queue()
        self._pool: asyncpg.Pool | None = None

    async def _ensure_pool(self):
        if self._pool is None:
            pg = self.config.postgres
            dsn = f"postgresql://{pg.user}:{pg.password}@{pg.host}:{pg.port}/{pg.database}"
            self._pool = await asyncpg.create_pool(dsn=dsn, min_size=1, max_size=4)
        return self._pool

    async def flush(self):
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
                        # BTC uses naive timestamp without time zone
                        ts_naive = self._to_naive_datetime_from_seconds(first.get("timestamp"))
                        await conn.execute(
                            """INSERT INTO btc_blocks (block_number, height, block_hash, ts)
                               VALUES ($1, $1, $2, $3)
                               ON CONFLICT (block_number) DO UPDATE
                               SET block_hash = EXCLUDED.block_hash, ts = EXCLUDED.ts""",
                            first.get("block_number"), first.get("block_hash"), ts_naive
                        )
                    for tx in items:
                        await self._insert_transaction(conn, tx)
                        await self._insert_utxos(conn, tx)
                        await self._mark_spent(conn, tx)
                    log.info(f"[BTC][DB] Atomic flush successful: {len(items)} txs")
                except Exception as e:
                    log.error(f"[BTC][DB] Atomic flush FAILED: {e}")
                    for item in items: await self.queue.put(item)
                    raise

    async def _insert_transaction(self, conn, tx):
        ts = self._to_naive_datetime_from_seconds(tx.get("timestamp"))
        await conn.execute(
            "INSERT INTO btc_transactions (tx_hash, block_hash, block_height, block_number, ts) VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING",
            tx.get("txid"), tx.get("block_hash"), tx.get("block_height"), tx.get("block_number"), ts
        )

    async def _insert_utxos(self, conn, tx):
        ts = self._to_aware_datetime_from_seconds(tx.get("timestamp"))
        for vout in tx.get("vout", []) or []:
            if vout.get("value") is None: continue
            value_sats = int(round(float(vout["value"]) * 100_000_000))
            address = vout.get("scriptPubKey", {}).get("address") or (vout.get("scriptPubKey", {}).get("addresses") or [None])[0]
            await conn.execute("INSERT INTO btc_utxos (txid, vout, address, amount_sats, ts) VALUES ($1, $2, $3, $4, $5)",
                               tx.get("txid"), vout.get("n"), address, value_sats, ts)

    async def _mark_spent(self, conn, tx):
        for vin in tx.get("vin", []) or []:
            if "txid" in vin and "vout" in vin:
                await conn.execute("UPDATE btc_utxos SET spent = TRUE, spent_by_txid = $1 WHERE txid = $2 AND vout = $3",
                                   tx.get("txid"), vin["txid"], vin["vout"])

    @staticmethod
    def _to_naive_datetime_from_seconds(v):
        return datetime.fromtimestamp(int(v), tz=timezone.utc).replace(tzinfo=None) if v else None
    @staticmethod
    def _to_aware_datetime_from_seconds(v):
        return datetime.fromtimestamp(int(v), tz=timezone.utc) if v else None
