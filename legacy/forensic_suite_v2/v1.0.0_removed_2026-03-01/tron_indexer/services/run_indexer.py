import asyncio
import os
import yaml
import aiohttp
import asyncpg
from datetime import datetime, timezone

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\tron_indexer\config\indexer.yaml")

USDT_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"


def load_config():
    print(f"[CONFIG] Loading config from {CONFIG_PATH}")
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    print("[CONFIG] Loaded successfully")
    return cfg


class TronQuickNodeIndexer:
    def __init__(self, config):
        print("[INIT] Initializing indexer…")

        self.config = config
        rpc_base = config["tron_rpc"]["base_url"].rstrip("/")
        self.rpc_json = rpc_base + "/jsonrpc"
        self.rpc_wallet = rpc_base + "/wallet"

        pg = config["database"]["postgres"]
        self.pg_dsn = (
            f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"
        )

        idx_cfg = config.get("indexer", {})
        self.workers = idx_cfg.get("worker_threads", 2)
        self.reorg_depth = idx_cfg.get("reorg_depth", 64)
        self.mode = idx_cfg.get("mode", "full")  # "full" or "fast_sync"
        self.start_override = idx_cfg.get("start_override")  # optional int
        self.fast_sync_lookback = idx_cfg.get("fast_sync_lookback", 500_000)
        self.batch_size = idx_cfg.get("batch_size", 100)

        self.timeout = config["tron_rpc"]["timeout"]
        self.max_retries = config["tron_rpc"]["max_retries"]

        self.poll_interval = 5.0  # slow, safe polling

        self.block_q = asyncio.Queue()
        self.tx_q = asyncio.Queue()
        self.db_q = asyncio.Queue()

        self.last_block_file = r"C:\development\tron_indexer\logs\last_block.txt"

        print("[INIT] Indexer initialized")

    async def rpc_call_with_timeout(self, func, *args, **kwargs):
        for attempt in range(1, self.max_retries + 1):
            try:
                return await asyncio.wait_for(func(*args, **kwargs), timeout=self.timeout)
            except asyncio.TimeoutError:
                print(f"[TIMEOUT] RPC call timed out (attempt {attempt}/{self.max_retries})")
            except Exception as e:
                print(f"[RPC ERROR] {e} (attempt {attempt}/{self.max_retries})")
            await asyncio.sleep(0.5)

        print("[RPC] Max retries exceeded — skipping")
        return None

    async def rpc_json_call(self, session, method, params):
        print(f"[RPC] Calling JSON-RPC method {method}")
        payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
        async with session.post(self.rpc_json, json=payload) as resp:
            resp.raise_for_status()
            return await resp.json()

    async def rpc_wallet_call(self, session, method, payload):
        print(f"[RPC] Calling wallet method {method}")
        async with session.post(f"{self.rpc_wallet}/{method}", json=payload) as resp:
            resp.raise_for_status()
            return await resp.json()

    async def get_last_checkpoint(self, conn):
        print("[DB] Loading checkpoint…")
        row = await conn.fetchrow("SELECT last_block FROM index_checkpoint WHERE id = 1")
        last = row["last_block"] if row else 0
        print(f"[DB] Last checkpoint block = {last}")
        return last

    async def update_checkpoint(self, conn, block_num):
        print(f"[DB] Updating checkpoint to block {block_num}")
        await conn.execute(
            "UPDATE index_checkpoint SET last_block = $1 WHERE id = 1",
            block_num,
        )
        os.makedirs(os.path.dirname(self.last_block_file), exist_ok=True)
        with open(self.last_block_file, "w", encoding="utf-8") as f:
            f.write(str(block_num))

    async def store_block_hash(self, conn, block_num, block_hash):
        print(f"[REORG] Storing block hash {block_hash} for block {block_num}")
        await conn.execute(
            """
            INSERT INTO block_hashes (block_number, block_hash)
            VALUES ($1, $2)
            ON CONFLICT (block_number) DO UPDATE SET block_hash = EXCLUDED.block_hash
            """,
            block_num,
            block_hash,
        )

    async def get_stored_block_hash(self, conn, block_num):
        row = await conn.fetchrow(
            "SELECT block_hash FROM block_hashes WHERE block_number = $1",
            block_num,
        )
        return row["block_hash"] if row else None

    async def rollback_from(self, conn, rollback_to):
        print(f"[REORG] Rolling back to block {rollback_to}")
        await conn.execute("DELETE FROM trc20_transfers WHERE block_number >= $1", rollback_to)
        await conn.execute("DELETE FROM address_tx_index WHERE block_number >= $1", rollback_to)
        await conn.execute("DELETE FROM trx_transfers WHERE block_number >= $1", rollback_to)
        await conn.execute("DELETE FROM transactions WHERE block_number >= $1", rollback_to)
        await conn.execute("DELETE FROM block_hashes WHERE block_number >= $1", rollback_to)
        await self.update_checkpoint(conn, rollback_to)

    async def get_latest_block_height(self, session):
        """
        Use QuickNode wallet API: /wallet/getnowblock
        """
        print("[HEAD] Fetching latest block height via getnowblock")
        now_block = await self.rpc_call_with_timeout(
            self.rpc_wallet_call,
            session,
            "getnowblock",
            {},
        )
        if not now_block:
            print("[HEAD] Failed to fetch latest block")
            return None

        header = now_block.get("block_header", {}).get("raw_data", {})
        latest_num = header.get("number")
        if latest_num is None:
            print("[HEAD] getnowblock returned no block number")
            return None

        print(f"[HEAD] Latest block on chain = {latest_num}")
        return int(latest_num)

    async def continuous_block_producer(self, session, start_block):
        """
        Continuous producer:
        - tracks current_block
        - polls latest height every poll_interval
        - enqueues only new blocks
        """
        current_block = start_block
        print(f"[BLOCK PRODUCER] Continuous mode starting at block {current_block}")

        while True:
            latest = await self.get_latest_block_height(session)
            if latest is None:
                print("[BLOCK PRODUCER] No latest height, sleeping…")
                await asyncio.sleep(self.poll_interval)
                continue

            if latest < current_block:
                print(f"[BLOCK PRODUCER] Chain height {latest} < current {current_block}, sleeping…")
                await asyncio.sleep(self.poll_interval)
                continue

            if latest == current_block:
                print(f"[BLOCK PRODUCER] No new blocks (at {latest}), sleeping…")
                await asyncio.sleep(self.poll_interval)
                continue

            print(f"[BLOCK PRODUCER] Enqueuing blocks {current_block} → {latest}")
            for b in range(current_block, latest + 1):
                await self.block_q.put(b)

            current_block = latest + 1
            await asyncio.sleep(self.poll_interval)

    async def block_worker(self, session, conn):
        print("[BLOCK WORKER] Worker started")
        while True:
            print("[BLOCK WORKER] Alive and waiting…")
            block_num = await self.block_q.get()
            if block_num is None:
                print("[BLOCK WORKER] Worker exiting")
                self.block_q.task_done()
                break

            print(f"[BLOCK] Fetching block {block_num}")

            block = await self.rpc_call_with_timeout(
                self.rpc_wallet_call,
                session,
                "getblockbynum",
                {"num": block_num},
            )

            if not block:
                print(f"[BLOCK] Failed to fetch block {block_num}")
                self.block_q.task_done()
                continue

            block_id = block.get("blockID")
            if not block_id:
                print(f"[BLOCK] Block {block_num} returned no blockID")
                self.block_q.task_done()
                continue

            stored_hash = await self.get_stored_block_hash(conn, block_num)
            if stored_hash and stored_hash != block_id:
                print(f"[REORG] Detected reorg at block {block_num}")
                rollback_to = max(0, block_num - self.reorg_depth)
                await self.rollback_from(conn, rollback_to)

            await self.store_block_hash(conn, block_num, block_id)

            txs = block.get("transactions", []) or []
            print(f"[BLOCK] Block {block_num} contains {len(txs)} txs")

            if not txs:
                # skip empty blocks entirely
                self.block_q.task_done()
                continue

            for tx in txs:
                txid = tx.get("txID")
                if txid:
                    print(f"[TX] Queueing tx {txid}")
                    await self.tx_q.put((block_num, txid))

            self.block_q.task_done()

    async def receipt_worker(self, session):
        print("[RECEIPT WORKER] Worker started")
        while True:
            print("[RECEIPT WORKER] Alive and waiting…")
            item = await self.tx_q.get()
            if item is None:
                print("[RECEIPT WORKER] Worker exiting")
                self.tx_q.task_done()
                break

            block_num, txid = item
            print(f"[RECEIPT] Fetching receipt for {txid}")

            receipt = await self.rpc_call_with_timeout(
                self.rpc_json_call,
                session,
                "eth_getTransactionReceipt",
                [txid],
            )

            if not receipt:
                print(f"[RECEIPT] Failed to fetch receipt for {txid}")
                self.tx_q.task_done()
                continue

            await self.db_q.put((block_num, txid, receipt))
            self.tx_q.task_done()

    async def db_worker(self):
        print("[DB WORKER] Worker started")
        conn = await asyncpg.connect(self.pg_dsn)

        batch = []

        while True:
            print("[DB WORKER] Alive and waiting…")
            item = await self.db_q.get()
            if item is None:
                # flush remaining
                for b in batch:
                    await self._process_db_item(conn, *b)
                batch.clear()
                self.db_q.task_done()
                break

            batch.append(item)
            self.db_q.task_done()

            if len(batch) >= self.batch_size:
                for b in batch:
                    await self._process_db_item(conn, *b)
                batch.clear()

        await conn.close()

    async def _process_db_item(self, conn, block_num, txid, receipt):
        await self.insert_tx(conn, block_num, txid, receipt)
        await self.update_checkpoint(conn, block_num)

    async def insert_tx(self, conn, block_num, txid, receipt):
        result = receipt.get("result") or {}
        logs = result.get("logs", [])
        block_ts = result.get("blockNumber", None)

        await conn.execute(
            """
            INSERT INTO transactions (txid, block_number, timestamp, status)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (txid) DO NOTHING
            """,
            txid,
            block_num,
            block_ts,
            result.get("status"),
        )

        now_ts = datetime.now(timezone.utc)

        for idx, log in enumerate(logs):
            if not log.get("topics"):
                continue
            if log["topics"][0] != USDT_TOPIC:
                continue

            print(f"[TRC20] Decoding TRC20 transfer in tx {txid}")

            contract = log.get("address")
            from_addr = "0x" + log["topics"][1][-40:]
            to_addr = "0x" + log["topics"][2][-40:]
            amount = int(log["data"], 16)

            await conn.execute(
                """
                INSERT INTO trc20_transfers
                (txid, log_index, contract_address, from_address, to_address, amount_raw, block_number, ts)
                VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
                """,
                txid,
                idx,
                contract,
                from_addr,
                to_addr,
                str(amount),
                block_num,
                now_ts,
            )

            await conn.execute(
                """
                INSERT INTO address_tx_index
                (address, txid, direction, contract_address, amount_raw, block_number, ts)
                VALUES ($1,$2,'out',$3,$4,$5,$6)
                """,
                from_addr,
                txid,
                contract,
                str(amount),
                block_num,
                now_ts,
            )

            await conn.execute(
                """
                INSERT INTO address_tx_index
                (address, txid, direction, contract_address, amount_raw, block_number, ts)
                VALUES ($1,$2,'in',$3,$4,$5,$6)
                """,
                to_addr,
                txid,
                contract,
                str(amount),
                block_num,
                now_ts,
            )

    async def run(self):
        print("[START] Connecting to Postgres…")
        conn = await asyncpg.connect(self.pg_dsn)
        last_block = await self.get_last_checkpoint(conn)
        await conn.close()

        async with aiohttp.ClientSession() as session:
            # base from checkpoint
            start_block = last_block + 1

            # optional override
            if self.start_override is not None and self.start_override > start_block:
                print(f"[START] Overriding start block to {self.start_override}")
                start_block = self.start_override

            # fast sync mode
            if self.mode == "fast_sync":
                latest = await self.get_latest_block_height(session)
                if latest is not None:
                    fs_start = max(0, latest - self.fast_sync_lookback)
                    if fs_start > start_block:
                        print(
                            f"[FAST SYNC] Starting at {fs_start} "
                            f"(latest={latest}, lookback={self.fast_sync_lookback})"
                        )
                        start_block = fs_start

            print(f"[START] Continuous indexing beginning at block {start_block}")

            conn_for_blocks = await asyncpg.connect(self.pg_dsn)

            # workers first
            block_workers = [
                asyncio.create_task(self.block_worker(session, conn_for_blocks))
                for _ in range(self.workers)
            ]
            receipt_workers = [
                asyncio.create_task(self.receipt_worker(session))
                for _ in range(self.workers)
            ]
            db_worker = asyncio.create_task(self.db_worker())

            # continuous producer (never returns under normal operation)
            producer = asyncio.create_task(self.continuous_block_producer(session, start_block))

            try:
                await producer
            except asyncio.CancelledError:
                print("[RUN] Producer cancelled, shutting down…")

            # graceful shutdown path (if we ever cancel producer)
            for _ in range(self.workers):
                await self.block_q.put(None)
            await self.block_q.join()

            for _ in range(self.workers):
                await self.tx_q.put(None)
            await self.tx_q.join()

            await self.db_q.put(None)
            await self.db_q.join()

            for w in block_workers + receipt_workers:
                w.cancel()
            db_worker.cancel()

            await conn_for_blocks.close()


if __name__ == "__main__":
    cfg = load_config()
    indexer = TronQuickNodeIndexer(cfg)
    asyncio.run(indexer.run())
