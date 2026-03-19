from fastapi import Depends
from .run_api import pg_pool

async def get_pg():
    async with pg_pool.acquire() as conn:
        yield conn
