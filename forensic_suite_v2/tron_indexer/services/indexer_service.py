class IndexerService:
    def __init__(self, config):
        self.checkpoint = Checkpoint(config)
        self.block_scanner = BlockScanner(config)
        self.reorg_detector = ReorgDetector(config)
        self.db_writer = DBWriter(config)
        self.receipt_workers = [ReceiptWorker(config, self.db_writer.queue) for _ in range(config.worker_threads)]

    def run(self):
        last_block = self.checkpoint.load()

        while True:
            block = last_block + 1

            blk_data = self.block_scanner.fetch(block)

            if self.reorg_detector.detect(block, blk_data):
                rollback_to = block - config.reorg_depth
                self.db_writer.rollback(rollback_to)
                last_block = rollback_to
                continue

            txids = blk_data.txids
            for txid in txids:
                self.receipt_workers.submit(txid)

            self.db_writer.flush()
            self.checkpoint.save(block)
            last_block = block
