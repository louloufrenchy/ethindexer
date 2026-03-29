import psycopg2
from psycopg2.extras import DictCursor

REQUIRED_TABLES = [
    "btc_blocks",
    "btc_transactions",
    "tron_blocks",
    "tron_transactions",
    "eth_blocks",
    "eth_transactions",
    "index_checkpoint",
    "indexer_metrics",
]

REQUIRED_UNIQUES = {
    "index_checkpoint": ["chain"],
}

def get_connection():
    return psycopg2.connect(
        host="192.168.0.28",
        port=5432,
        user="postgres",
        password="Str0ngPassw0rd2025",
        dbname="forensic",
    )


def validate_tables(cur):
    for table in REQUIRED_TABLES:
        cur.execute(
            """
            SELECT to_regclass(%s)
            """,
            (table,),
        )
        exists = cur.fetchone()[0] is not None
        if not exists:
            raise RuntimeError(f"Missing required table: {table}")


def validate_uniques(cur):
    for table, cols in REQUIRED_UNIQUES.items():
        for col in cols:
            cur.execute(
                """
                SELECT 1
                FROM pg_constraint c
                JOIN pg_class t ON c.conrelid = t.oid
                JOIN pg_namespace n ON t.relnamespace = n.oid
                JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY (c.conkey)
                WHERE c.contype = 'u'
                  AND n.nspname = 'public'
                  AND t.relname = %s
                  AND a.attname = %s
                LIMIT 1
                """,
                (table, col),
            )
            if cur.fetchone() is None:
                raise RuntimeError(
                    f"Missing UNIQUE constraint on {table}({col}) required by indexer engine"
                )


def run_schema_validation():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=DictCursor) as cur:
            print("=== Running Schema Compatibility Validator ===")
            validate_tables(cur)
            validate_uniques(cur)
            print("[OK] Schema validation passed. Safe to start indexers.")

async def validate_schema(pg_cfg):
    """
    Async wrapper used by indexer runners.
    The indexers expect this function to exist.
    """
    run_schema_validation()

if __name__ == "__main__":
    run_schema_validation()
