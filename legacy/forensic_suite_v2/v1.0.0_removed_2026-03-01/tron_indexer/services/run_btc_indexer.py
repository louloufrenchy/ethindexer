import asyncio
import os
import yaml
import aiohttp
import asyncpg
from datetime import datetime, timezone
from base64 import b64encode

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\tron_indexer\config\indexer.yaml")


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


class BtcIndexer:
    def __init__(self, config):
        self.config = config
        rpc = config["btc_rpc"]
        self.rpc_url = rpc["base_url"]
        auth_str = f"{rpc['username']}:{rpc['password']}".encode("utf-8")
        self.auth_header = "Basic " + b64encode(auth_str).decode("ascii")
        self.timeout = rpc["timeout"]
        self.max_retries = rpc["max_retries"]

        pg = config["database"]["postgres"]
        self.pg_dsn = (
            f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"
        )

        idx_cfg = config.get("indexer", {})
        self.workers = idx_cfg.get("worker_threads", 2)
        self.batch_size = idx_cfg.get("batch_size", 100)
        self.poll_interval = 10.0

        self.block_q = asyncio.Queue()
        self.db_q = asyncio.Queue()

    async def rpc_call(self, session, method, params):
        payload = {"jsonrpc": "1.0", "id": "btc", "method": method, "params": params}
        headers = {"Authorization": self.auth_header}
        for attempt in range(1, self.max_retries + 1):
            try:
                async with session.post(
                    self.rpc_url, json=payload, headers=headers, timeout=self.timeout
                ) as resp:
                    resp.raise_for_status()
                    return await resp.json()
            except Exception as e:
                print(f"[BTC RPC ERROR] {e} (attempt {attempt}/{self.max_retries})")
                await asyncio.sleep(0.5)
        print("[BTC RPC] Max retries exceeded")
        return None

    async def get_block_count(self, session):
        data = await self.rpc_call(session, "getblockcount", [])
        if not data or "result" not in data:
            return None
        return int(data["result"])

    async def get_last_checkpoint(self, conn):
        row = await conn.fetchrow("SELECT last_block FROM index_checkpoint WHERE id = 3")
        return row["last_block"] if row else 0

    async def update_checkpoint(self, conn, height):
        await conn.execute(
            """
            INSERT INTO index_checkpoint (id, last_block)
            VALUES (3, $1)
            ON CONFLICT (id) DO UPDATE SET last_block = EXCLUDED.last_block
            """,
            height,
        )

    async def continuous_block_producer(self, session, start_height):
        current = start_height
        print(f"[BTC PRODUCER] Starting at height {current}")
        while True:
            latest = await self.get_block_count(session)
            if latest is None:
                await asyncio.sleep(self.poll_interval)
                continue

            if latest < current:
                await asyncio.sleep(self.poll_interval)
                continue

            if latest == current:
                await asyncio.sleep(self.poll_interval)
                continue

            print(f"[BTC PRODUCER] Enqueuing heights {current} → {latest}")
            for h in range(current, latest + 1):
                await self.block_q.put(h)

            current = latest + 1
            await asyncio.sleep(self.poll_interval)

    async def block_worker(self, session):
        print("[BTC BLOCK WORKER] Started")
        while True:
            height = await self.block_q.get()
            if height is None:
                self.block_q.task_done()
                break

            print(f"[BTC BLOCK] Fetching height {height}")
            data_hash = await self.rpc_call(session, "getblockhash", [height])
            if not data_hash or "result" not in data_hash:
                print(f"[BTC BLOCK] Failed getblockhash {height}")
                self.block_q.task_done()
                continue

            block_hash = data_hash["result"]
            data_block = await self.rpc_call(session, "getblock", [block_hash, 2])
            if not data_block or "result" not in data_block:
                print(f"[BTC BLOCK] Failed getblock {block_hash}")
                self.block_q.task_done()
                continue

            block = data_block["result"]
            await self.db_q.put((height, block_hash, block))
            self.block_q.task_done()

    async def db_worker(self):
        print("[BTC DB WORKER] Started")
        conn = await asyncpg.connect(self.pg_dsn)
        batch = []
        while True:
            item = await self.db_q.get()
            if item is None:
                for b in batch:
                    await self._process_block(conn, *b)
                batch.clear()
                self.db_q.task_done()
                break

            batch.append(item)
            self.db_q.task_done()

            if len(batch) >= self.batch_size:
                for b in batch:
                    await self._process_block(conn, *b)
                batch.clear()

        await conn.close()

    async def _process_block(self, conn, height, block_hash, block):
        ts = block.get("time")
        await conn.execute(
            """
            INSERT INTO btc_blocks (block_hash, height, timestamp)
            VALUES ($1, $2, $3)
            ON CONFLICT (block_hash) DO NOTHING
            """,
            block_hash,
            height,
            ts,
        )

        for tx in block.get("tx", []):
            txid = tx.get("txid")
            await conn.execute(
                """
                INSERT INTO btc_transactions (txid, block_hash, block_height, timestamp)
                VALUES ($1, $2, $3, $4)
                ON CONFLICT (txid) DO NOTHING
                """,
                txid,
                block_hash,
                height,
                ts,
            )

            # UTXO indexing
            for vout in tx.get("vout", []):
                n = vout.get("n")
                value = vout.get("value", 0)
                script_pub_key = vout.get("scriptPubKey", {})
                addresses = script_pub_key.get("addresses") or []
                address = addresses[0] if addresses else None
                sats = int(value * 100_000_000)

                await conn.execute(
                    """
                    INSERT INTO btc_utxos (txid, vout, address, amount_sats, spent)
                    VALUES ($1, $2, $3, $4, FALSE)
                    """,
                    txid,
                    n,
                    address,
                    sats,
                )

            for vin in tx.get("vin", []):
                prev_txid = vin.get("txid")
                vout_index = vin.get("vout")
                if prev_txid is not None and vout_index is not None:
                    await conn.execute(
                        """
                        UPDATE btc_utxos
                        SET spent = TRUE, spent_by_txid = $3
                        WHERE txid = $1 AND vout = $2
                        """,
                        prev_txid,
                        vout_index,
                        txid,
                    )

        await self.update_checkpoint(conn, height)
        await self.insert_metrics(conn, height)

    async def insert_metrics(self, conn, last_height):
        async with aiohttp.ClientSession() as session:
            data = await self.rpc_call(session, "getblockcount", [])
        if not data or "result" not in data:
            return
        head = int(data["result"])
        lag = head - last_height
        ts = datetime.now(timezone.utc)
        await conn.execute(
            """
            INSERT INTO indexer_metrics (ts, chain, last_block, chain_head, lag)
            VALUES ($1, 'btc', $2, $3, $4)
            """,
            ts,
            last_height,
            head,
            lag,
        )

    async def run(self):
        print("[BTC] Connecting to Postgres…")
        conn = await asyncpg.connect(self.pg_dsn)
        last_height = await self.get_last_checkpoint(conn)
        await conn.close()

        async with aiohttp.ClientSession() as session:
            start_height = last_height + 1
            print(f"[BTC] Continuous indexing beginning at height {start_height}")

            block_workers = [
                asyncio.create_task(self.block_worker(session))
                for _ in range(self.workers)
            ]
            db_worker = asyncio.create_task(self.db_worker())
            producer = asyncio.create_task(self.continuous_block_producer(session, start_height))

            try:
                await producer
            except asyncio.CancelledError:
                print("[BTC] Producer cancelled")

            for _ in range(self.workers):
                await self.block_q.put(None)
            await self.block_q.join()

            await self.db_q.put(None)
            await self.db_q.join()

            for w in block_workers:
                w.cancel()
            db_worker.cancel()


if __name__ == "__main__":
    cfg = load_config()
    indexer = BtcIndexer(cfg)
    asyncio.run(indexer.run())
