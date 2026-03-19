import asyncio
import os
import yaml
import aiohttp
import asyncpg
from datetime import datetime, timezone
from forensic_suite_v2.btc_indexer.services.run_btc_indexer_v2 import main as run_btc
from forensic_suite_v2.eth_indexer.services.run_eth_indexer_v2 import main as run_eth
from forensic_suite_v2.tron_indexer.services.run_tron_indexer_v2 import main as run_tron

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\eth_indexer\config\indexer.yaml")

# --- Performance tuning knobs ---
BATCH_SIZE_NORMAL = 500
BATCH_SIZE_CATCHUP = 3000

NUM_DB_WORKERS_NORMAL = 3
NUM_DB_WORKERS_CATCHUP = 4

QUEUE_DEPTH_WARN = 5000
CATCHUP_LAG_THRESHOLD = 10_000  # blocks
METRICS_INTERVAL = 5  # seconds


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


class EthIndexer:
    def __init__(self, config):
        self.config = config
        rpc_base = config["eth_rpc"]["base_url"].rstrip("/")
        self.rpc_url = rpc_base
        self.timeout = config["eth_rpc"]["timeout"]
        self.max_retries = config["eth_rpc"]["max_retries"]

        pg = config["database"]["postgres"]
        self.pg_dsn = (
            f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"
        )

        idx_cfg = config.get("indexer", {})
        self.workers = idx_cfg.get("worker_threads", 2)
        self.mode = idx_cfg.get("mode", "full")
        self.fast_sync_lookback = idx_cfg.get("fast_sync_lookback", 500_000)
        self.start_override = idx_cfg.get("start_override")
        self.poll_interval = 5.0

        # dynamic performance knobs
        self.batch_size = BATCH_SIZE_NORMAL
        self.num_db_workers = NUM_DB_WORKERS_NORMAL
        self.last_processed_block = None

        self.block_q = asyncio.Queue()
        self.tx_q = asyncio.Queue()
        self.db_q = asyncio.Queue()

    async def rpc_call(self, session, method, params):
        payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
        for attempt in range(1, self.max_retries + 1):
            try:
                async with session.post(self.rpc_url, json=payload, timeout=self.timeout) as resp:
                    resp.raise_for_status()
                    return await resp.json()
            except Exception as e:
                print(f"[ETH RPC ERROR] {e} (attempt {attempt}/{self.max_retries})")
                await asyncio.sleep(0.5)
        print("[ETH RPC] Max retries exceeded")
        return None

    async def get_latest_block_height(self, session):
        print("[ETH HEAD] Fetching latest block number")
        data = await self.rpc_call(session, "eth_blockNumber", [])
        if not data or "result" not in data:
            print("[ETH HEAD] Failed to fetch block number")
            return None
        return int(data["result"], 16)

    async def get_last_checkpoint(self, conn):
        row = await conn.fetchrow("SELECT last_block FROM index_checkpoint WHERE id = 2")
        return row["last_block"] if row else 0

    async def update_checkpoint(self, conn, block_num):
        await conn.execute(
            """
            INSERT INTO index_checkpoint (id, last_block)
            VALUES (2, $1)
            ON CONFLICT (id) DO UPDATE SET last_block = EXCLUDED.last_block
            """,
            block_num,
        )

    async def continuous_block_producer(self, session, start_block):
        current_block = start_block
        print(f"[ETH PRODUCER] Continuous mode starting at block {current_block}")
        while True:
            latest = await self.get_latest_block_height(session)
            if latest is None:
                await asyncio.sleep(self.poll_interval)
                continue

            if latest <= current_block:
                await asyncio.sleep(self.poll_interval)
                continue

            print(f"[ETH PRODUCER] Enqueuing blocks {current_block} → {latest}")
            for b in range(current_block, latest + 1):
                await self.block_q.put(b)

            current_block = latest + 1
            await asyncio.sleep(self.poll_interval)

    async def block_worker(self, session):
        print("[ETH BLOCK WORKER] Started")
        while True:
            block_num = await self.block_q.get()
            if block_num is None:
                self.block_q.task_done()
                break

            print(f"[ETH BLOCK] Fetching block {block_num}")
            hex_num = hex(block_num)
            data = await self.rpc_call(
                session,
                "eth_getBlockByNumber",
                [hex_num, True],
            )
            if not data or "result" not in data:
                print(f"[ETH BLOCK] Failed to fetch block {block_num}")
                self.block_q.task_done()
                continue

            block = data["result"]
            txs = block.get("transactions", []) or []
            print(f"[ETH BLOCK] Block {block_num} contains {len(txs)} txs")

            if not txs:
                self.block_q.task_done()
                continue

            for tx in txs:
                tx_hash = tx.get("hash")
                if tx_hash:
                    await self.tx_q.put((block_num, tx_hash, tx))

            self.block_q.task_done()

    async def receipt_worker(self, session):
        print("[ETH RECEIPT WORKER] Started")
        while True:
            item = await self.tx_q.get()
            if item is None:
                self.tx_q.task_done()
                break

            block_num, tx_hash, tx_obj = item
            print(f"[ETH RECEIPT] Fetching receipt for {tx_hash}")
            data = await self.rpc_call(
                session,
                "eth_getTransactionReceipt",
                [tx_hash],
            )
            if not data or "result" not in data:
                print(f"[ETH RECEIPT] Failed for {tx_hash}")
                self.tx_q.task_done()
                continue

            receipt = data["result"]
            await self.db_q.put((block_num, tx_hash, tx_obj, receipt))
            self.tx_q.task_done()

    async def db_worker(self, worker_id: int):
        print(f"[ETH DB WORKER {worker_id}] Started")
        conn = await asyncpg.connect(self.pg_dsn)

        while True:
            batch = []

            # Always block for at least one item
            item = await self.db_q.get()
            if item is None:
                self.db_q.task_done()
                break

            batch.append(item)
            self.db_q.task_done()

            # Drain queue up to batch_size
            try:
                for _ in range(self.batch_size - 1):
                    item = self.db_q.get_nowait()
                    if item is None:
                        self.db_q.task_done()
                        break
                    batch.append(item)
                    self.db_q.task_done()
            except asyncio.QueueEmpty:
                pass

            await self._process_batch(conn, batch)

        await conn.close()

    async def _process_batch(self, conn, batch):
        tx_rows = []
        erc20_rows = []
        addr_rows = []

        now_ts = datetime.now(timezone.utc)
        last_block = None

        for block_num, tx_hash, tx_obj, receipt in batch:
            last_block = block_num

            # eth_transactions
            ts = int(tx_obj.get("blockNumber", "0x0"), 16) if tx_obj.get("blockNumber") else None
            status = receipt.get("status")

            tx_rows.append((tx_hash, block_num, ts, status))

            # ERC-20 logs
            logs = receipt.get("logs", []) or []
            for idx, log in enumerate(logs):
                topics = log.get("topics") or []
                if not topics:
                    continue

                # ERC-20 Transfer signature
                if topics[0].lower() != "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef":
                    continue

                # Guard against malformed logs
                if len(topics) < 3:
                    print(f"[ETH WARN] Malformed ERC20 log (missing topics) tx={tx_hash}")
                    continue
                if len(topics[1]) < 42 or len(topics[2]) < 42:
                    print(f"[ETH WARN] Malformed ERC20 log (short topics) tx={tx_hash}")
                    continue

                from_addr = "0x" + topics[1][-40:]
                to_addr   = "0x" + topics[2][-40:]

                raw_data = log.get("data") or "0x0"
                if raw_data == "0x":
                    raw_data = "0x0"
                amount = int(raw_data, 16)

                contract = log.get("address")

                erc20_rows.append(
                    (tx_hash, idx, contract, from_addr, to_addr, str(amount), block_num, now_ts)
                )

                addr_rows.append((from_addr, tx_hash, "out", contract, str(amount), block_num, now_ts))
                addr_rows.append((to_addr,   tx_hash, "in",  contract, str(amount), block_num, now_ts))

        if tx_rows:
            await conn.executemany(
                """
                INSERT INTO eth_transactions (tx_hash, block_number, timestamp, status)
                VALUES ($1,$2,$3,$4)
                ON CONFLICT (tx_hash) DO NOTHING
                """,
                tx_rows,
            )

        if erc20_rows:
            await conn.executemany(
                """
                INSERT INTO erc20_transfers
                (tx_hash, log_index, contract_address, from_address, to_address,
                 amount_raw, block_number, ts)
                VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
                """,
                erc20_rows,
            )

        if addr_rows:
            await conn.executemany(
                """
                INSERT INTO eth_address_index
                (address, tx_hash, direction, contract_address, amount_raw,
                 block_number, ts)
                VALUES ($1,$2,$3,$4,$5,$6,$7)
                """,
                addr_rows,
            )

        if last_block is not None:
            await self.update_checkpoint(conn, last_block)
            self.last_processed_block = last_block

    async def queue_monitor(self):
        while True:
            await asyncio.sleep(5)
            size = self.db_q.qsize()
            print(f"[ETH QUEUE] DB queue size: {size}")
            if size > QUEUE_DEPTH_WARN:
                print(f"[ETH QUEUE] WARNING: depth {size} > {QUEUE_DEPTH_WARN}")

    async def metrics_worker(self):
        while True:
            await asyncio.sleep(METRICS_INTERVAL)

            try:
                if self.last_processed_block is None:
                    continue

                async with aiohttp.ClientSession() as session:
                    head_data = await self.rpc_call(session, "eth_blockNumber", [])
                if not head_data or "result" not in head_data:
                    continue

                head = int(head_data["result"], 16)
                lag = head - self.last_processed_block

                # Catch-up mode
                if lag > CATCHUP_LAG_THRESHOLD:
                    if self.batch_size != BATCH_SIZE_CATCHUP:
                        print(f"[ETH MODE] Entering CATCH-UP mode (lag={lag})")
                    self.batch_size = BATCH_SIZE_CATCHUP
                    self.num_db_workers = NUM_DB_WORKERS_CATCHUP
                else:
                    if self.batch_size != BATCH_SIZE_NORMAL:
                        print(f"[ETH MODE] Returning to NORMAL mode (lag={lag})")
                    self.batch_size = BATCH_SIZE_NORMAL
                    self.num_db_workers = NUM_DB_WORKERS_NORMAL

                conn = await asyncpg.connect(self.pg_dsn)
                try:
                    await conn.execute(
                        """
                        INSERT INTO indexer_metrics (ts, chain, last_block, chain_head, lag)
                        VALUES (NOW(), 'eth', $1, $2, $3)
                        """,
                        self.last_processed_block,
                        head,
                        lag,
                    )
                finally:
                    await conn.close()

                print(f"[ETH METRICS] block={self.last_processed_block} head={head} lag={lag}")

            except asyncio.CancelledError:
                # allow clean shutdown
                raise
            except Exception as e:
                print(f"[ETH METRICS ERROR] {e}")
                # don’t crash the indexer, just skip this cycle
                continue

    async def run(self):
        cfg = self.config
        print("[ETH] Connecting to Postgres…")
        conn = await asyncpg.connect(self.pg_dsn)
        last_block = await self.get_last_checkpoint(conn)
        await conn.close()

        async with aiohttp.ClientSession() as session:
            start_block = last_block + 1

            if self.mode == "fast_sync":
                latest = await self.get_latest_block_height(session)
                if latest is not None:
                    fs_start = max(0, latest - self.fast_sync_lookback)
                    if fs_start > start_block:
                        print(
                            f"[ETH FAST SYNC] Starting at {fs_start} "
                            f"(latest={latest}, lookback={self.fast_sync_lookback})"
                        )
                        start_block = fs_start

            if self.start_override is not None and self.start_override > start_block:
                print(f"[ETH] Overriding start block to {self.start_override}")
                start_block = self.start_override

            print(f"[ETH] Continuous indexing beginning at block {start_block}")

            block_workers = [
                asyncio.create_task(self.block_worker(session))
                for _ in range(self.workers)
            ]
            receipt_workers = [
                asyncio.create_task(self.receipt_worker(session))
                for _ in range(self.workers)
            ]

            # DB workers (initial count; metrics_worker may adjust num_db_workers dynamically,
            # but for this run we keep the initial set)
            db_workers = [
                asyncio.create_task(self.db_worker(i))
                for i in range(self.num_db_workers)
            ]

            producer = asyncio.create_task(self.continuous_block_producer(session, start_block))
            metrics_task = asyncio.create_task(self.metrics_worker())
            queue_task = asyncio.create_task(self.queue_monitor())

            try:
                await asyncio.gather(
                    producer,
                    *db_workers,
                    metrics_task,
                    queue_task,
                    *block_workers,
                    *receipt_workers,
                )
            except asyncio.CancelledError:
                print("[ETH] Producer cancelled")

            for _ in range(self.workers):
                await self.block_q.put(None)
            await self.block_q.join()

            for _ in range(self.workers):
                await self.tx_q.put(None)
            await self.tx_q.join()

            for _ in range(self.num_db_workers):
                await self.db_q.put(None)
            await self.db_q.join()

            for w in block_workers + receipt_workers + db_workers:
                w.cancel()
            metrics_task.cancel()
            queue_task.cancel()


if __name__ == "__main__":
    cfg = load_config()
    indexer = EthIndexer(cfg)
    asyncio.run(indexer.run())