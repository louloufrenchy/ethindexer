import asyncio

class EthReceiptWorker:
    def __init__(self, config, queue):
        self.config = config
        self.queue = queue

    async def submit(self, txid: str) -> None:
        # Push txid into the shared DB writer queue
        await self.queue.put(txid)
        await asyncio.sleep(0)
