import os
import yaml
import asyncpg
from fastapi import FastAPI
from routers import address, health, tokens

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\tron_indexer\config\indexer.yaml")

def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

app = FastAPI()
pg_pool = None

@app.on_event("startup")
async def startup():
    global pg_pool
    cfg = load_config()
    pg = cfg["database"]["postgres"]
    dsn = f"postgres://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"
    pg_pool = await asyncpg.create_pool(dsn)

@app.on_event("shutdown")
async def shutdown():
    await pg_pool.close()

app.include_router(address.router)
app.include_router(health.router)
app.include_router(tokens.router)
