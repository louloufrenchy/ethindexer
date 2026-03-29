import psycopg2
import json
from pathlib import Path
import time

CHAIN = "eth"   # change to btc or tron
JSON_PATH = Path(rf"C:\forensic_state\{CHAIN}\{CHAIN}_checkpoint.json")

pg = {
    "host": "192.168.0.28",
    "port": 5432,
    "user": "postgres",
    "password": "<YOUR_PASSWORD>",
    "database": "forensic",
}

def get_db_checkpoint():
    conn = psycopg2.connect(**pg)
    cur = conn.cursor()
    cur.execute("SELECT last_block FROM index_checkpoint WHERE chain=%s", (CHAIN,))
    row = cur.fetchone()
    conn.close()
    return row[0] if row else None

def get_json_checkpoint():
    if not JSON_PATH.exists():
        return None
    try:
        data = json.loads(JSON_PATH.read_text())
        return int(data.get("last_block"))
    except Exception:
        return None

print(f"Monitoring checkpoints for chain: {CHAIN}")
print("Press CTRL+C to stop.\n")

last_db = None

while True:
    db_val = get_db_checkpoint()
    json_val = get_json_checkpoint()

    if db_val != last_db:
        print(f"[UPDATE] DB={db_val}  JSON={json_val}")
        last_db = db_val

    if db_val != json_val:
        print(f"[WARNING] Drift detected! DB={db_val}, JSON={json_val}")

    time.sleep(2)
