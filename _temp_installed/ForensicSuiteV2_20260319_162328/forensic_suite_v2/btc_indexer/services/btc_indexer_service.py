from forensic_suite_v2.core.indexer_engine import BaseIndexerService

class BtcIndexerService(BaseIndexerService):
    chain_name = "btc"

    def build_checkpoint(self):
        from .checkpoint import BtcCheckpoint
        return BtcCheckpoint(self.config)

    def build_block_scanner(self):
        from .block_scanner import BtcBlockScanner
        return BtcBlockScanner(self.config)

    def build_reorg_detector(self):
        from .reorg_detector import BtcReorgDetector
        return BtcReorgDetector(self.config)

    def build_db_writer(self):
        from .db_writer import BtcDBWriter
        return BtcDBWriter(self.config)

    def build_receipt_workers(self):
        from .receipt_worker import BtcReceiptWorker
        return [
            BtcReceiptWorker(self.config, self.db_writer.queue)
            for _ in range(self.config.worker_threads)
        ]

    async def get_chain_head(self) -> int:
        return await self.block_scanner.get_chain_head()