import asyncpg
import sys
<<<<<<< HEAD
from typing import Dict, List, Tuple
=======
from typing import Dict, List
>>>>>>> master


EXPECTED_SCHEMA = {
    "btc_blocks": {
        "columns": {
            "block_number": "bigint",
            "block_hash": "text",
<<<<<<< HEAD
            "ts": "timestamp without time zone"
        },
        "primary_key": ["block_number"]
=======
            "ts": "timestamp without time zone",
        },
        "primary_key": ["block_number"],
>>>>>>> master
    },
    "btc_transactions": {
        "columns": {
            "tx_hash": "text",
            "block_number": "bigint",
<<<<<<< HEAD
            "ts": "timestamp without time zone"
        },
        "primary_key": ["tx_hash"]
=======
            "ts": "timestamp without time zone",
        },
        "primary_key": ["tx_hash"],
>>>>>>> master
    },
    "tron_blocks": {
        "columns": {
            "block_number": "bigint",
            "block_hash": "text",
<<<<<<< HEAD
            "ts": "timestamp without time zone"
        },
        "primary_key": ["block_number"]
=======
            "ts": "timestamp without time zone",
        },
        "primary_key": ["block_number"],
>>>>>>> master
    },
    "tron_transactions": {
        "columns": {
            "tx_hash": "text",
            "block_number": "bigint",
<<<<<<< HEAD
            "ts": "timestamp without time zone"
        },
        "primary_key": ["tx_hash"]
=======
            "ts": "timestamp without time zone",
        },
        "primary_key": ["tx_hash"],
>>>>>>> master
    },
    "eth_blocks": {
        "columns": {
            "block_number": "bigint",
            "block_hash": "text",
<<<<<<< HEAD
            "ts": "timestamp without time zone"
        },
        "primary_key": ["block_number"]
=======
            "ts": "timestamp without time zone",
        },
        "primary_key": ["block_number"],
>>>>>>> master
    },
    "eth_transactions": {
        "columns": {
            "tx_hash": "text",
            "block_number": "bigint",
            "ts": "timestamp without time zone",
<<<<<<< HEAD
            "status": "integer"
        },
        "primary_key": ["tx_hash"]
=======
            "status": "integer",
        },
        "primary_key": ["tx_hash"],
>>>>>>> master
    },
    "index_checkpoint": {
        "columns": {
            "id": "integer",
<<<<<<< HEAD
            "last_block": "bigint"
        },
        "primary_key": ["id"]
=======
            "last_block": "bigint",
        },
        "primary_key": ["id"],
>>>>>>> master
    },
    "indexer_metrics": {
        "columns": {
            "ts": "timestamp without time zone",
            "chain": "text",
            "last_block": "bigint",
            "chain_head": "bigint",
<<<<<<< HEAD
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
=======
            "lag": "bigint",
        },
        "primary_key": [],
    },
}


def _safe_print(message: str) -> None:
    """
    Print safely in Windows service / redirected stdout environments where
    cp1252 or other narrow encodings may reject Unicode symbols.
    """
    try:
        print(message)
    except UnicodeEncodeError:
        fallback = (
            message.encode("ascii", errors="replace")
            .decode("ascii", errors="replace")
        )
        print(fallback)


async def fetch_table_columns(conn, table: str) -> Dict[str, str]:
    rows = await conn.fetch(
        """
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_name = $1
        """,
        table,
    )
>>>>>>> master
    return {r["column_name"]: r["data_type"] for r in rows}


async def fetch_primary_key(conn, table: str) -> List[str]:
<<<<<<< HEAD
    rows = await conn.fetch("""
=======
    rows = await conn.fetch(
        """
>>>>>>> master
        SELECT a.attname
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = $1::regclass AND i.indisprimary
<<<<<<< HEAD
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
=======
        """,
        table,
    )
    return [r["attname"] for r in rows]


async def validate_table(conn, table: str, spec: Dict) -> bool:
    _safe_print(f"Validating table: {table}")

    exists = await conn.fetchval(
        """
        SELECT EXISTS (
            SELECT 1 FROM information_schema.tables WHERE table_name = $1
        )
        """,
        table,
    )

    if not exists:
        _safe_print(f"[FAIL] Missing table: {table}")
        return False

>>>>>>> master
    actual_cols = await fetch_table_columns(conn, table)
    expected_cols = spec["columns"]

    for col, coltype in expected_cols.items():
        if col not in actual_cols:
<<<<<<< HEAD
            print(f"❌ ERROR: Missing column {col} in {table}")
            return False
        if actual_cols[col] != coltype:
            print(f"❌ ERROR: Column type mismatch in {table}.{col}: expected {coltype}, got {actual_cols[col]}")
            return False

    # Check primary key
=======
            _safe_print(f"[FAIL] Missing column {col} in {table}")
            return False
        if actual_cols[col] != coltype:
            _safe_print(
                f"[FAIL] Column type mismatch in {table}.{col}: "
                f"expected {coltype}, got {actual_cols[col]}"
            )
            return False

>>>>>>> master
    expected_pk = spec["primary_key"]
    actual_pk = await fetch_primary_key(conn, table)

    if expected_pk != actual_pk:
<<<<<<< HEAD
        print(f"❌ ERROR: Primary key mismatch in {table}: expected {expected_pk}, got {actual_pk}")
        return False

    print(f"✅ OK: {table}")
    return True


async def validate_schema(pg_cfg: Dict):
=======
        _safe_print(
            f"[FAIL] Primary key mismatch in {table}: "
            f"expected {expected_pk}, got {actual_pk}"
        )
        return False

    _safe_print(f"[OK] {table}")
    return True


async def validate_schema(pg_cfg: Dict) -> None:
>>>>>>> master
    conn = await asyncpg.connect(
        host=pg_cfg["host"],
        port=pg_cfg["port"],
        user=pg_cfg["user"],
        password=pg_cfg["password"],
<<<<<<< HEAD
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
=======
        database=pg_cfg["database"],
    )

    try:
        _safe_print("=== Running Schema Compatibility Validator ===")

        all_ok = True
        for table, spec in EXPECTED_SCHEMA.items():
            ok = await validate_table(conn, table, spec)
            if not ok:
                all_ok = False

        if not all_ok:
            _safe_print("[FAIL] Schema validation failed. Aborting indexer startup.")
            sys.exit(1)

        _safe_print("[OK] Schema validation passed. Safe to start indexers.")
    finally:
        await conn.close()
>>>>>>> master
