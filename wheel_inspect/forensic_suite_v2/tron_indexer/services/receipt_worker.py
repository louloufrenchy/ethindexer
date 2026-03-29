import asyncio

class TronReceiptWorker:
    def __init__(self, config, queue):
        self.config = config
        self.queue = queue

    async def submit(self, txid: str) -> None:
        await self.queue.put(txid)
        await asyncio.sleep(0)
