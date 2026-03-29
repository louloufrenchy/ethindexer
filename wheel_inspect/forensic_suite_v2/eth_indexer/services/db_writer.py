import asyncio

class EthDBWriter:
    def __init__(self, config):
        self.config = config
        # Shared queue for receipt workers
        self.queue: asyncio.Queue[str] = asyncio.Queue()

    async def rollback(self, height: int) -> None:
        # Stub rollback
        await asyncio.sleep(0)

    async def flush(self) -> None:
        # Drain the queue in dry-run mode
        while not self.queue.empty():
            _ = await self.queue.get()
            self.queue.task_done()
        await asyncio.sleep(0)
