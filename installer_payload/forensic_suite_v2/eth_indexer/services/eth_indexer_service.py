from typing import Any

from forensic_suite_v2.core.indexer_engine import BaseIndexerService


class EthIndexerService(BaseIndexerService):
    chain_name = "eth"

    def build_checkpoint(self):
        from .checkpoint import EthCheckpoint
        return EthCheckpoint(self.config)

    def build_block_scanner(self):
        from .block_scanner import EthBlockScanner
        return EthBlockScanner(self.config)

    def build_reorg_detector(self):
        from .reorg_detector import EthReorgDetector
        return EthReorgDetector(self.config)

    def build_db_writer(self):
        from .db_writer import EthDBWriter
        return EthDBWriter(self.config)

    def build_receipt_workers(self):
        from .receipt_worker import EthReceiptWorker
        return [
            EthReceiptWorker(self.config, self.db_writer.queue)
            for _ in range(self.config.worker_threads)
        ]

    async def get_chain_head(self) -> int:
        return await self.block_scanner.get_chain_head()

    async def upsert_block_record(self, height: int, blk: Any) -> None:
        await self.db_writer.upsert_eth_block_record(
            block_number=height,
            block_hash=getattr(blk, "block_hash", None),
            timestamp=getattr(blk, "timestamp", None),
        )
