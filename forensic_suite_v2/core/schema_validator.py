import asyncpg
import sys
from typing import Dict, List, Tuple


EXPECTED_SCHEMA = {
    "btc_blocks": {
        "columns": {
            "block_number": "bigint",
            "block_hash": "text",
            "ts": "timestamp without time zone"
        },
        "primary_key": ["block_number"]
    },
    "btc_transactions": {
        "columns": {
            "tx_hash": "text",
            "block_number": "bigint",
            "ts": "timestamp without time zone"
        },
        "primary_key": ["tx_hash"]
    },
    "tron_blocks": {
        "columns": {
            "block_number": "bigint",
            "block_hash": "text",
            "ts": "timestamp without time zone"
        },
        "primary_key": ["block_number"]
    },
    "tron_transactions": {
        "columns": {
            "tx_hash": "text",
            "block_number": "bigint",
            "ts": "timestamp without time zone"
        },
        "primary_key": ["tx_hash"]
    },
    "eth_blocks": {
        "columns": {
            "block_number": "bigint",
            "block_hash": "text",
            "ts": "timestamp without time zone"
        },
        "primary_key": ["block_number"]
    },
    "eth_transactions": {
        "columns": {
            "tx_hash": "text",
            "block_number": "bigint",
            "ts": "timestamp without time zone",
            "status": "integer"
        },
        "primary_key": ["tx_hash"]
    },
    "index_checkpoint": {
        "columns": {
            "id": "integer",
            "last_block": "bigint"
        },
        "primary_key": ["id"]
    },
    "indexer_metrics": {
        "columns": {
            "ts": "timestamp without time zone",
            "chain": "text",
            "last_block": "bigint",
            "chain_head": "bigint",
            "lag": "bigint"
        },
        "primary_key": []
    }
}


async def fetch_table_columns(conn, table: str) -> Dict[str, str]:
    rows = await conn.fetch("""
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_name = $1
    """, table)
    return {r["column_name"]: r["data_type"] for r in rows}


async def fetch_primary_key(conn, table: str) -> List[str]:
    rows = await conn.fetch("""
        SELECT a.attname
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = $1::regclass AND i.indisprimary
    """, table)
    return [r["attname"] for r in rows]


async def validate_table(conn, table: str, spec: Dict):
    print(f"Validating table: {table}")

    # Check table exists
    exists = await conn.fetchval("""
        SELECT EXISTS (
            SELECT 1 FROM information_schema.tables WHERE table_name = $1
        )
    """, table)

    if not exists:
        print(f"❌ ERROR: Missing table: {table}")
        return False

    # Check columns
    actual_cols = await fetch_table_columns(conn, table)
    expected_cols = spec["columns"]

    for col, coltype in expected_cols.items():
        if col not in actual_cols:
            print(f"❌ ERROR: Missing column {col} in {table}")
            return False
        if actual_cols[col] != coltype:
            print(f"❌ ERROR: Column type mismatch in {table}.{col}: expected {coltype}, got {actual_cols[col]}")
            return False

    # Check primary key
    expected_pk = spec["primary_key"]
    actual_pk = await fetch_primary_key(conn, table)

    if expected_pk != actual_pk:
        print(f"❌ ERROR: Primary key mismatch in {table}: expected {expected_pk}, got {actual_pk}")
        return False

    print(f"✅ OK: {table}")
    return True


async def validate_schema(pg_cfg: Dict):
    conn = await asyncpg.connect(
        host=pg_cfg["host"],
        port=pg_cfg["port"],
        user=pg_cfg["user"],
        password=pg_cfg["password"],
        database=pg_cfg["database"]
    )

    print("=== Running Schema Compatibility Validator ===")

    all_ok = True
    for table, spec in EXPECTED_SCHEMA.items():
        ok = await validate_table(conn, table, spec)
        if not ok:
            all_ok = False

    await conn.close()

    if not all_ok:
        print("❌ Schema validation failed. Aborting indexer startup.")
        sys.exit(1)

    print("🎉 Schema validation passed. Safe to start indexers.")
