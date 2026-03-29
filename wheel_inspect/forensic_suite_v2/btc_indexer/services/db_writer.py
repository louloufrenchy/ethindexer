import asyncio

class BtcDBWriter:
    def __init__(self, config):
        self.config = config
        self.queue: asyncio.Queue[str] = asyncio.Queue()

    async def rollback(self, height: int) -> None:
        await asyncio.sleep(0)

    async def flush(self) -> None:
        while not self.queue.empty():
            _ = await self.queue.get()
            self.queue.task_done()
        await asyncio.sleep(0)
