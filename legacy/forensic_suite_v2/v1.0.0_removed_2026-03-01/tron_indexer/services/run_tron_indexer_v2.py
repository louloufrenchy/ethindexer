import asyncio
import os
import yaml
import aiohttp
import asyncpg
from datetime import datetime, timezone, timedelta

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\tron_indexer\config\indexer.yaml")

USDT_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

# --- Performance tuning knobs ---
BATCH_SIZE_NORMAL = 200
BATCH_SIZE_CATCHUP = 1500

NUM_DB_WORKERS_NORMAL = 1
NUM_DB_WORKERS_CATCHUP = 3

QUEUE_DEPTH_WARN = 10_000
CATCHUP_LAG_THRESHOLD = 10_000
CATCHUP_EXIT_THRESHOLD = 500
METRICS_INTERVAL = 5


def load_config():
    print(f"[CONFIG] Loading config from {CONFIG_PATH}")
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    print("[CONFIG] Loaded successfully")
    return cfg


class TronQuickNodeIndexerV2:
    def __init__(self, config):
        print("[INIT] Initializing TRON indexer v2.0…")

        self.config = config
        tron_cfg = config["tron_rpc"]
        rpc_base = tron_cfg["base_url"].rstrip("/")
        self.rpc_json_endpoints = tron_cfg.get("json_endpoints") or [rpc_base + "/jsonrpc"]
        self.rpc_wallet_endpoints = tron_cfg.get("wallet_endpoints") or [rpc_base + "/wallet"]

        self.rpc_json_idx = 0
        self.rpc_wallet_idx = 0

        pg = config["database"]["postgres"]
        self.pg_dsn = (
            f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"
        )

        idx_cfg = config.get("indexer", {})
        self.workers = idx_cfg.get("worker_threads", 2)
        self.reorg_depth = idx_cfg.get("reorg_depth", 64)
        self.mode = idx_cfg.get("mode", "full")
        self.start_override = idx_cfg.get("start_override")
        self.fast_sync_lookback = idx_cfg.get("fast_sync_lookback", 500_000)

        self.timeout = tron_cfg["timeout"]
        self.max_retries = tron_cfg["max_retries"]

        self.poll_interval = 5.0

        self.batch_size = BATCH_SIZE_NORMAL
        self.num_db_workers = NUM_DB_WORKERS_NORMAL
        self.last_processed_block = None
        self.current_mode = "realtime"  # or "catchup"

        self.block_q = asyncio.Queue()
        self.tx_q = asyncio.Queue()
        self.db_q = asyncio.Queue()

        self.last_block_file = r"C:\development\tron_indexer\logs\last_block.txt"

        print("[INIT] TRON indexer v2.0 initialized")

    # ---------------- RPC endpoint rotation ----------------

    def _next_json_endpoint(self):
        ep = self.rpc_json_endpoints[self.rpc_json_idx]
        self.rpc_json_idx = (self.rpc_json_idx + 1) % len(self.rpc_json_endpoints)
        return ep

    def _next_wallet_endpoint(self):
        ep = self.rpc_wallet_endpoints[self.rpc_wallet_idx]
        self.rpc_wallet_idx = (self.rpc_wallet_idx + 1) % len(self.rpc_wallet_endpoints)
        return ep

    # ---------------- RPC helpers ----------------

    async def rpc_call_with_timeout(self, func, *args, **kwargs):
        last_exc = None
        for attempt in range(1, self.max_retries + 1):
            try:
                return await asyncio.wait_for(func(*args, **kwargs), timeout=self.timeout)
            except asyncio.TimeoutError as e:
                last_exc = e
                print(f"[TIMEOUT] RPC call timed out (attempt {attempt}/{self.max_retries})")
            except Exception as e:
                last_exc = e
                print(f"[RPC ERROR] {e} (attempt {attempt}/{self.max_retries})")
            await asyncio.sleep(0.5)

        print(f"[RPC] Max retries exceeded — skipping (last error: {last_exc})")
        return None

    async def rpc_json_call(self, session, method, params):
        endpoint = self._next_json_endpoint()
        payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
        async with session.post(endpoint, json=payload) as resp:
            resp.raise_for_status()
            return await resp.json()

    async def rpc_wallet_call(self, session, method, payload):
        endpoint = self._next_wallet_endpoint()
        async with session.post(f"{endpoint}/{method}", json=payload) as resp:
            resp.raise_for_status()
            return await resp.json()

    # ---------------- DB helpers ----------------

    async def get_last_checkpoint(self, conn):
        print("[DB] Loading checkpoint…")
        row = await conn.fetchrow("SELECT last_block FROM index_checkpoint WHERE id = 1")
        last = row["last_block"] if row else 0
        print(f"[DB] Last checkpoint block = {last}")
        return last

    async def update_checkpoint(self, conn, block_num):
        await conn.execute(
            """
            INSERT INTO index_checkpoint (id, last_block)
            VALUES (1, $1)
            ON CONFLICT (id) DO UPDATE SET last_block = EXCLUDED.last_block
            """,
            block_num,
        )
        os.makedirs(os.path.dirname(self.last_block_file), exist_ok=True)
        with open(self.last_block_file, "w", encoding="utf-8") as f:
            f.write(str(block_num))

    async def store_block_hash(self, conn, block_num, block_hash):
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

    # ---------------- Partition helpers ----------------

    async def ensure_monthly_partitions(self, conn, ts: datetime):
        month_start = ts.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        next_month = (month_start + timedelta(days=32)).replace(day=1)
        start_str = month_start.strftime("%Y-%m-%d")
        end_str = next_month.strftime("%Y-%m-%d")
        suffix = month_start.strftime("%Y_%m")

        # trc20_transfers
        await conn.execute(
            f"""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_class
                    WHERE relname = 'trc20_transfers_{suffix}'
                ) THEN
                    EXECUTE $ct$
                        CREATE TABLE trc20_transfers_{suffix}
                        PARTITION OF trc20_transfers
                        FOR VALUES FROM ('{start_str}') TO ('{end_str}');
                    $ct$;
                END IF;
            END$$;
            """
        )

        # address_tx_index
        await conn.execute(
            f"""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_class
                    WHERE relname = 'address_tx_index_{suffix}'
                ) THEN
                    EXECUTE $ct$
                        CREATE TABLE address_tx_index_{suffix}
                        PARTITION OF address_tx_index
                        FOR VALUES FROM ('{start_str}') TO ('{end_str}');
                    $ct$;
                END IF;
            END$$;
            """
        )

        # transactions
        await conn.execute(
            f"""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_class
                    WHERE relname = 'transactions_{suffix}'
                ) THEN
                    EXECUTE $ct$
                        CREATE TABLE transactions_{suffix}
                        PARTITION OF transactions
                        FOR VALUES FROM ('{start_str}') TO ('{end_str}');
                    $ct$;
                END IF;
            END$$;
            """
        )

        # contract_log_density
        await conn.execute(
            f"""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_class
                    WHERE relname = 'contract_log_density_{suffix}'
                ) THEN
                    EXECUTE $ct$
                        CREATE TABLE contract_log_density_{suffix}
                        PARTITION OF contract_log_density
                        FOR VALUES FROM ('{start_str}') TO ('{end_str}');
                    $ct$;
                END IF;
            END$$;
            """
        )

    # ---------------- Chain head / producer ----------------

    async def get_latest_block_height(self, session):
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

    # ---------------- Workers ----------------

    async def block_worker(self, session, conn):
        print("[BLOCK WORKER] Worker started")
        while True:
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
                self.block_q.task_done()
                continue

            for tx in txs:
                txid = tx.get("txID")
                if txid:
                    await self.tx_q.put((block_num, txid))

            self.block_q.task_done()

    async def receipt_worker(self, session):
        print("[RECEIPT WORKER] Worker started")
        while True:
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

    async def db_worker(self, worker_id: int):
        print(f"[DB WORKER {worker_id}] Worker started")
        conn = await asyncpg.connect(self.pg_dsn)

        while True:
            batch = []

            item = await self.db_q.get()
            if item is None:
                self.db_q.task_done()
                break

            batch.append(item)
            self.db_q.task_done()

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
        trc20_rows = []
        addr_rows = []
        density_rows = []

        last_block = None
        last_ts = None

        for block_num, txid, receipt in batch:
            last_block = block_num

            result = receipt.get("result") or receipt
            logs = result.get("logs", []) or []

            raw_block_num = result.get("blockNumber")
            block_number_int = None
            if raw_block_num is not None:
                if isinstance(raw_block_num, str) and raw_block_num.startswith("0x"):
                    try:
                        block_number_int = int(raw_block_num, 16)
                    except Exception:
                        print(f"[WARN] Invalid blockNumber hex: {raw_block_num}")
                        block_number_int = None
                else:
                    block_number_int = raw_block_num

            # block timestamp from blockNumber is not directly available in receipt;
            # we align ts by using chain time via NOW() but partition-aware.
            # If you later pass block timestamp in receipt, plug it here.
            ts = datetime.now(timezone.utc)
            last_ts = ts

            status = result.get("status")
            tx_rows.append((txid, block_num, ts, status))

            # contract-level density aggregation per batch
            contract_counts = {}

            for idx, log in enumerate(logs):
                topics = log.get("topics") or []
                if not topics:
                    continue

                contract = log.get("address")
                if contract:
                    contract_counts[contract] = contract_counts.get(contract, 0) + 1

                if topics[0] != USDT_TOPIC:
                    continue

                if len(topics) < 3:
                    print(f"[TRC20 WARN] Malformed TRC20 log (missing topics) tx={txid}")
                    continue
                if len(topics[1]) < 42 or len(topics[2]) < 42:
                    print(f"[TRC20 WARN] Malformed TRC20 log (short topics) tx={txid}")
                    continue

                print(f"[TRC20] Decoding TRC20 transfer in tx {txid}")

                from_addr = "0x" + topics[1][-40:]
                to_addr = "0x" + topics[2][-40:]

                raw_data = log.get("data") or "0x0"
                if raw_data == "0x":
                    raw_data = "0x0"
                amount = int(raw_data, 16)

                trc20_rows.append(
                    (txid, idx, contract, from_addr, to_addr, str(amount), block_num, ts)
                )

                addr_rows.append(
                    (from_addr, txid, "out", contract, str(amount), block_num, ts)
                )
                addr_rows.append(
                    (to_addr, txid, "in", contract, str(amount), block_num, ts)
                )

            for contract, count in contract_counts.items():
                density_rows.append((ts, contract, count, block_num))

        if last_ts is not None:
            await self.ensure_monthly_partitions(conn, last_ts)

        if tx_rows:
            await conn.executemany(
                """
                INSERT INTO transactions (txid, block_number, timestamp, status)
                VALUES ($1, $2, $3, $4)
                ON CONFLICT (txid, timestamp) DO NOTHING
                """,
                tx_rows,
            )

        if trc20_rows:
            await conn.executemany(
                """
                INSERT INTO trc20_transfers
                (txid, log_index, contract_address, from_address, to_address,
                 amount_raw, block_number, ts)
                VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
                """,
                trc20_rows,
            )

        if addr_rows:
            await conn.executemany(
                """
                INSERT INTO address_tx_index
                (address, txid, direction, contract_address, amount_raw,
                 block_number, ts)
                VALUES ($1,$2,$3,$4,$5,$6,$7)
                """,
                addr_rows,
            )

        if density_rows:
            await conn.executemany(
                """
                INSERT INTO contract_log_density
                (ts, contract_address, log_count, block_number)
                VALUES ($1,$2,$3,$4)
                """,
                density_rows,
            )

        if last_block is not None:
            await self.update_checkpoint(conn, last_block)
            self.last_processed_block = last_block

    # ---------------- Monitoring / metrics ----------------

    async def queue_monitor(self):
        while True:
            await asyncio.sleep(5)
            size = self.db_q.qsize()
            print(f"[TRON QUEUE] DB queue size: {size}")
            if size > QUEUE_DEPTH_WARN:
                print(f"[TRON QUEUE] WARNING: depth {size} > {QUEUE_DEPTH_WARN}")

    async def metrics_worker(self):
        while True:
            await asyncio.sleep(METRICS_INTERVAL)

            try:
                if self.last_processed_block is None:
                    continue

                async with aiohttp.ClientSession() as session:
                    head = await self.get_latest_block_height(session)
                if head is None:
                    continue

                lag = head - self.last_processed_block

                prev_mode = self.current_mode
                if lag > CATCHUP_LAG_THRESHOLD:
                    self.current_mode = "catchup"
                    self.batch_size = BATCH_SIZE_CATCHUP
                    self.num_db_workers = NUM_DB_WORKERS_CATCHUP
                elif lag < CATCHUP_EXIT_THRESHOLD:
                    self.current_mode = "realtime"
                    self.batch_size = BATCH_SIZE_NORMAL
                    self.num_db_workers = NUM_DB_WORKERS_NORMAL

                if self.current_mode != prev_mode:
                    print(f"[TRON MODE] Switched from {prev_mode} to {self.current_mode} (lag={lag})")

                conn = await asyncpg.connect(self.pg_dsn)
                try:
                    await conn.execute(
                        """
                        INSERT INTO indexer_metrics
                        (ts, chain, last_block, chain_head, lag, mode, db_queue_depth)
                        VALUES (NOW(), 'tron', $1, $2, $3, $4, $5)
                        """,
                        self.last_processed_block,
                        head,
                        lag,
                        self.current_mode,
                        self.db_q.qsize(),
                    )
                finally:
                    await conn.close()

                print(
                    f"[TRON METRICS] block={self.last_processed_block} "
                    f"head={head} lag={lag} mode={self.current_mode}"
                )

            except asyncio.CancelledError:
                raise
            except Exception as e:
                print(f"[TRON METRICS ERROR] {e}")
                continue

    # ---------------- Run ----------------

    async def run(self):
        print("[START] Connecting to Postgres…")
        conn = await asyncpg.connect(self.pg_dsn)
        last_block = await self.get_last_checkpoint(conn)
        await conn.close()

        async with aiohttp.ClientSession() as session:
            start_block = last_block + 1

            if self.start_override is not None and self.start_override > start_block:
                print(f"[START] Overriding start block to {self.start_override}")
                start_block = self.start_override

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

            print(f"[START] Continuous TRON v2.0 indexing beginning at block {start_block}")

            block_worker_conns = []
            block_workers = []
            for _ in range(self.workers):
                bw_conn = await asyncpg.connect(self.pg_dsn)
                block_worker_conns.append(bw_conn)
                block_workers.append(
                    asyncio.create_task(self.block_worker(session, bw_conn))
                )

            receipt_workers = [
                asyncio.create_task(self.receipt_worker(session))
                for _ in range(self.workers)
            ]
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
                print("[RUN] Producer cancelled, shutting down…")

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

            for bw_conn in block_worker_conns:
                await bw_conn.close()


if __name__ == "__main__":
    cfg = load_config()
    indexer = TronQuickNodeIndexerV2(cfg)
    asyncio.run(indexer.run())
