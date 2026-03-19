from __future__ import annotations

import asyncio
import logging
import time
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional, Tuple

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

        # Chain-specific components (must be implemented by subclasses)
        self.checkpoint = self.build_checkpoint()
        self.block_scanner = self.build_block_scanner()
        self.reorg_detector = self.build_reorg_detector()
        self.db_writer = self.build_db_writer()
        self.receipt_workers = self.build_receipt_workers()

    # -------------------------------------------------------------------
    # Abstract Factory Methods (subclasses implement these)
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
    # Core Engine
    # -------------------------------------------------------------------
    async def run(self) -> None:
        last_block = await self.checkpoint.load()
        log.info("Starting indexer", extra={"chain": self.chain_name, "start_block": last_block})

        while True:
            head = await self.get_chain_head()
            CHAIN_HEAD.labels(self.chain_name).set(head)

            # Determine fetch range
            start = last_block + 1
            end = min(start + self.max_parallel - 1, head)

            if start > end:
                await asyncio.sleep(0.5)
                continue

            # Parallel block fetch
            blocks = await self._fetch_blocks_parallel(start, end)

            # Process blocks sequentially (ordered)
            for height, blk in blocks:
                last_block = await self._process_block(height, blk)

            CURRENT_HEIGHT.labels(self.chain_name).set(last_block)
            CHAIN_LAG.labels(self.chain_name).set(head - last_block)

    # -------------------------------------------------------------------
    # Parallel Block Fetching
    # -------------------------------------------------------------------
    async def _fetch_blocks_parallel(self, start: int, end: int) -> List[Tuple[int, Any]]:
        tasks = []
        for height in range(start, end + 1):
            tasks.append(self._fetch_block(height))

        results = await asyncio.gather(*tasks)
        return sorted(results, key=lambda x: x[0])

    async def _fetch_block(self, height: int) -> Tuple[int, Any]:
        with BLOCK_FETCH_LATENCY.labels(self.chain_name).time():
            blk = await self.block_scanner.fetch(height)
        return height, blk

    # -------------------------------------------------------------------
    # Block Processing
    # -------------------------------------------------------------------
    async def _process_block(self, height: int, blk: Any) -> int:
        # Reorg detection
        if await self.reorg_detector.detect(height, blk):
            REORG_EVENTS.labels(self.chain_name).inc()
            rollback_to = max(0, height - self.reorg_depth)
            log.info("Reorg detected", extra={"chain": self.chain_name, "rollback_to": rollback_to})

            await self.db_writer.rollback(rollback_to)
            await self.checkpoint.save(rollback_to)

            # Adaptive reorg-depth tuning
            self.reorg_depth = min(self.reorg_depth + 1, 50)
            return rollback_to

        # Submit txids to workers
        for txid in blk.txids:
            worker = self.receipt_workers[height % len(self.receipt_workers)]
            await worker.submit(txid)

        # Write block
        with BLOCK_WRITE_LATENCY.labels(self.chain_name).time():
            await self.db_writer.flush()

        await self.checkpoint.save(height)

        # Adaptive reorg-depth tuning (decay)
        if self.reorg_depth > self.config.reorg_depth:
            self.reorg_depth -= 0.1

        await asyncio.sleep(0.05)

        return height
