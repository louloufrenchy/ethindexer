from __future__ import annotations

import asyncio
import logging
import time
from abc import ABC, abstractmethod
from typing import Any, List, Tuple

from prometheus_client import Counter, Gauge, Histogram
import orjson


# -------------------------------------------------------------------
# Structured JSON Logger
# -------------------------------------------------------------------
class JsonLogger(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        base = {
            "msg": msg,
            "ts": time.time(),
            "component": "indexer_engine",
        }
        if "extra" in kwargs:
            base.update(kwargs["extra"])
            del kwargs["extra"]
        return orjson.dumps(base).decode(), kwargs


log = JsonLogger(logging.getLogger("indexer_engine"), {})


# -------------------------------------------------------------------
# Prometheus Metrics
# -------------------------------------------------------------------
BLOCK_FETCH_LATENCY = Histogram(
    "indexer_block_fetch_latency_seconds",
    "Time spent fetching a block",
    ["chain"],
)

BLOCK_WRITE_LATENCY = Histogram(
    "indexer_block_write_latency_seconds",
    "Time spent writing a block to DB",
    ["chain"],
)

REORG_EVENTS = Counter(
    "indexer_reorg_events_total",
    "Number of reorg events detected",
    ["chain"],
)

CURRENT_HEIGHT = Gauge(
    "indexer_current_height",
    "Last indexed block height",
    ["chain"],
)

CHAIN_HEAD = Gauge(
    "indexer_chain_head",
    "Current chain head height",
    ["chain"],
)

CHAIN_LAG = Gauge(
    "indexer_chain_lag",
    "Chain lag (head - indexed)",
    ["chain"],
)


# -------------------------------------------------------------------
# Generic Base Class
# -------------------------------------------------------------------
class BaseIndexerService(ABC):
    """
    Generic async indexer engine with:
    - parallel block fetchers
    - structured logging
    - Prometheus metrics
    - adaptive reorg-depth tuning
    """

    chain_name: str
    config: Any

    def __init__(self, config: Any):
        self.config = config
        self.reorg_depth = config.reorg_depth
        self.max_parallel = config.parallel_fetchers

        self.checkpoint = self.build_checkpoint()
        self.block_scanner = self.build_block_scanner()
        self.reorg_detector = self.build_reorg_detector()
        self.db_writer = self.build_db_writer()
        self.receipt_workers = self.build_receipt_workers()

    # -------------------------------------------------------------------
    # Abstract Factory Methods
    # -------------------------------------------------------------------
    @abstractmethod
    def build_checkpoint(self): ...

    @abstractmethod
    def build_block_scanner(self): ...

    @abstractmethod
    def build_reorg_detector(self): ...

    @abstractmethod
    def build_db_writer(self): ...

    @abstractmethod
    def build_receipt_workers(self) -> List[Any]: ...

    @abstractmethod
    async def get_chain_head(self) -> int: ...

    # -------------------------------------------------------------------
    # Optional per-chain block metadata hook
    # -------------------------------------------------------------------
    async def upsert_block_record(self, height: int, blk: Any) -> None:
        await asyncio.sleep(0)

    # -------------------------------------------------------------------
    # Core Engine
    # -------------------------------------------------------------------
    async def run(self) -> None:
        last_block = await self.checkpoint.load()

        log.info(
            "Starting indexer",
            extra={"chain": self.chain_name, "start_block": last_block},
        )

        while True:
            try:
                head = await self.get_chain_head()
                CHAIN_HEAD.labels(self.chain_name).set(head)

                start = last_block + 1
                end = min(start + self.max_parallel - 1, head)

                if start > end:
                    await asyncio.sleep(0.5)
                    continue

                log.info(
                    "Fetching block window",
                    extra={
                        "chain": self.chain_name,
                        "start": start,
                        "end": end,
                        "head": head,
                        "last_block": last_block,
                    },
                )

                blocks = await self._fetch_blocks_parallel(start, end)

                for height, blk in blocks:
                    last_block = await self._process_block(height, blk)

                    if not getattr(self.config, "dry_run", False):
                        await self.checkpoint.save(last_block)
                        log.info(
                            "Checkpoint saved",
                            extra={
                                "chain": self.chain_name,
                                "last_block": last_block,
                            },
                        )

                CURRENT_HEIGHT.labels(self.chain_name).set(last_block)
                CHAIN_LAG.labels(self.chain_name).set(head - last_block)

            except Exception as exc:  # noqa: BLE001
                log.exception(
                    "Indexer loop failed",
                    extra={
                        "chain": self.chain_name,
                        "error": repr(exc),
                    },
                )
                await asyncio.sleep(1.0)

    # -------------------------------------------------------------------
    # Block Processing
    # -------------------------------------------------------------------
    async def _process_block(self, height: int, blk: Any) -> int:
        try:
            log.info(
                "Processing block",
                extra={
                    "chain": self.chain_name,
                    "height": height,
                },
            )

            if blk is None:
                raise RuntimeError(f"{self.chain_name} block fetch returned None at height {height}")

            txids = getattr(blk, "txids", None)
            if txids is None:
                raise RuntimeError(
                    f"{self.chain_name} block object missing txids at height {height}: {type(blk).__name__}"
                )

            await self.upsert_block_record(height, blk)

            tx_count = len(txids)

            log.info(
                "Block fetched",
                extra={
                    "chain": self.chain_name,
                    "height": height,
                    "tx_count": tx_count,
                },
            )

            # ---------------------------------------------------------
            # 1. Reorg detection
            # ---------------------------------------------------------
            if await self.reorg_detector.detect(height, blk):
                REORG_EVENTS.labels(self.chain_name).inc()
                rollback_to = max(0, height - self.reorg_depth)

                log.info(
                    "Reorg detected",
                    extra={
                        "chain": self.chain_name,
                        "height": height,
                        "rollback_to": rollback_to,
                    },
                )

                await self.db_writer.rollback(rollback_to)

                if not getattr(self.config, "dry_run", False):
                    await self.checkpoint.save(rollback_to)
                    log.info(
                        "Rollback checkpoint saved",
                        extra={
                            "chain": self.chain_name,
                            "rollback_to": rollback_to,
                        },
                    )

                self.reorg_depth = min(self.reorg_depth + 1, 50)
                return rollback_to

            # ---------------------------------------------------------
            # 2. Submit txids to receipt workers in bounded batches
            # ---------------------------------------------------------
            if tx_count == 0:
                log.info(
                    "Block has no transactions",
                    extra={
                        "chain": self.chain_name,
                        "height": height,
                    },
                )
            else:
                batch_size = int(getattr(self.config, "receipt_batch_size", 10))
                block_hash = getattr(blk, "block_hash", None)

                for batch_start in range(0, tx_count, batch_size):
                    batch_txids = txids[batch_start: batch_start + batch_size]

                    log.info(
                        "Submitting txid batch to receipt workers",
                        extra={
                            "chain": self.chain_name,
                            "height": height,
                            "batch_start": batch_start,
                            "batch_size": len(batch_txids),
                            "tx_count": tx_count,
                        },
                    )

                    tasks = []
                    for offset, txid in enumerate(batch_txids):
                        worker = self.receipt_workers[(batch_start + offset) % len(self.receipt_workers)]
                        tasks.append(
                            worker.submit(
                                txid,
                                height,
                                block_hash,
                            )
                        )

                    results = await asyncio.gather(*tasks, return_exceptions=True)

                    failures = 0
                    for idx, result in enumerate(results):
                        if isinstance(result, Exception):
                            failures += 1
                            log.exception(
                                "Receipt worker submit failed",
                                extra={
                                    "chain": self.chain_name,
                                    "height": height,
                                    "txid": batch_txids[idx],
                                    "error": repr(result),
                                },
                            )

                    log.info(
                        "Receipt batch complete",
                        extra={
                            "chain": self.chain_name,
                            "height": height,
                            "batch_start": batch_start,
                            "batch_size": len(batch_txids),
                            "failures": failures,
                            "queue_size": self.db_writer.queue.qsize(),
                        },
                    )

            # ---------------------------------------------------------
            # 3. Flush DB writes
            # ---------------------------------------------------------
            log.info(
                "Flushing db writer",
                extra={
                    "chain": self.chain_name,
                    "height": height,
                    "tx_count": tx_count,
                    "queue_size": self.db_writer.queue.qsize(),
                },
            )

            with BLOCK_WRITE_LATENCY.labels(self.chain_name).time():
                await self.db_writer.flush()

            log.info(
                "Block committed",
                extra={
                    "chain": self.chain_name,
                    "height": height,
                    "tx_count": tx_count,
                },
            )

            if self.reorg_depth > self.config.reorg_depth:
                self.reorg_depth -= 0.1

            await asyncio.sleep(0.05)
            return height

        except Exception as exc:  # noqa: BLE001
            log.exception(
                "Block processing failed",
                extra={
                    "chain": self.chain_name,
                    "height": height,
                    "error": repr(exc),
                },
            )
            raise

    # -------------------------------------------------------------------
    # Parallel Block Fetching
    # -------------------------------------------------------------------
    async def _fetch_blocks_parallel(self, start: int, end: int) -> List[Tuple[int, Any]]:
        tasks = [self._fetch_block(height) for height in range(start, end + 1)]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        good_results: List[Tuple[int, Any]] = []
        for offset, result in enumerate(results):
            height = start + offset
            if isinstance(result, Exception):
                log.exception(
                    "Block fetch failed",
                    extra={
                        "chain": self.chain_name,
                        "height": height,
                        "error": repr(result),
                    },
                )
                raise result
            good_results.append(result)

        return sorted(good_results, key=lambda x: x[0])

    async def _fetch_block(self, height: int) -> Tuple[int, Any]:
        log.info(
            "Fetching block",
            extra={
                "chain": self.chain_name,
                "height": height,
            },
        )
        with BLOCK_FETCH_LATENCY.labels(self.chain_name).time():
            blk = await self.block_scanner.fetch(height)
        return height, blk
