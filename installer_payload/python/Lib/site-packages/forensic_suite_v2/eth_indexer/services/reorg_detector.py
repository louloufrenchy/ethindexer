class EthReorgDetector:
    def __init__(self, config):
        self.config = config

    async def detect(self, height, blk) -> bool:
        return False
