import asyncpg, asyncio

async def test():
    conn = await asyncpg.connect("postgres://tron:tronpass@localhost:5432/tron_index")
    rows = await conn.fetch("SELECT relname FROM pg_class WHERE relname LIKE 'btc%'")
    print(rows)
    row = await conn.fetchval("SHOW search_path")
    print("search_path =", row)
    await conn.close()

asyncio.run(test())

