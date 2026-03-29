import asyncpg
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from datetime import datetime

DB_DSN = "postgresql://postgres:Str0ngPassw0rd2025@192.168.0.28:5432/forensic"

app = FastAPI()
app.mount("/static", StaticFiles(directory="forensic_suite_v2/dashboards/web/static"), name="static")


async def get_conn():
    return await asyncpg.connect(dsn=DB_DSN)


@app.get("/")
async def root():
    return FileResponse("forensic_suite_v2/dashboards/web/static/index.html")


@app.get("/metrics/summary")
async def metrics_summary():
    conn = await get_conn()
    try:
        rows = await conn.fetch(
            "SELECT chain, last_block, updated_at FROM index_checkpoint ORDER BY chain"
        )
        data = [
            {
                "chain": r["chain"],
                "last_block": r["last_block"],
                "updated_at": r["updated_at"].isoformat(),
            }
            for r in rows
        ]
        return {"ts": datetime.now().isoformat(), "checkpoints": data}
    finally:
        await conn.close()


@app.get("/metrics/transactions")
async def metrics_transactions():
    conn = await get_conn()
    try:
        result = {}
        for chain, table in [
            ("eth", "eth_transactions"),
            ("btc", "btc_transactions"),
            ("tron", "tron_transactions"),
        ]:
            try:
                c = await conn.fetchval(f"SELECT COUNT(*) FROM {table}")
            except Exception:
                c = None
            result[chain] = c
        return {"ts": datetime.now().isoformat(), "counts": result}
    finally:
        await conn.close()
