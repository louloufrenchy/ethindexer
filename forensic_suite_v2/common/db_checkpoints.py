# forensic_suite_v2/common/db_checkpoints.py

from pathlib import Path
import json
import psycopg2


# ============================================================
# DB → canonical checkpoint loader
# ============================================================
def load_db_checkpoint(conn, chain: str) -> int | None:
    """
    Return the last_block for the given chain from the DB.
    Returns None if no row exists.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT last_block FROM index_checkpoint WHERE chain = %s",
            (chain,),
        )
        row = cur.fetchone()
        return int(row[0]) if row else None


# ============================================================
# DB → canonical checkpoint writer
# ============================================================
def write_db_checkpoint(conn, chain: str, last_block: int) -> None:
    """
    Insert or update the canonical checkpoint in the DB.
    """
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO index_checkpoint (chain, last_block)
            VALUES (%s, %s)
            ON CONFLICT (chain)
            DO UPDATE SET
                last_block = EXCLUDED.last_block,
                updated_at = NOW()
            """,
            (chain, last_block),
        )
    conn.commit()


# ============================================================
# JSON → mirror loader
# ============================================================
def load_json_checkpoint(path: Path) -> int | None:
    """
    Load checkpoint from JSON mirror.
    Returns None if file missing or invalid.
    """
    if not path.exists():
        return None

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return int(data.get("last_block"))
    except Exception:
        return None


# ============================================================
# JSON → mirror writer
# ============================================================
def write_json_checkpoint(path: Path, last_block: int) -> None:
    """
    Write checkpoint to JSON mirror.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"last_block": int(last_block)}
    path.write_text(json.dumps(payload), encoding="utf-8")


# ============================================================
# Startup resolver (DB → JSON → YAML)
# ============================================================
def resolve_start_block(conn, chain: str, yaml_start_block: int, json_path: Path) -> int:
    """
    Determine the correct starting block for an indexer:

        1. Prefer DB (canonical)
        2. Fallback to JSON (mirror)
        3. Fallback to YAML (initial seed)

    Always mirrors whichever source is chosen.
    Returns the block to START FROM (i.e., last_block + 1).
    """

    # 1) DB canonical
    db_block = load_db_checkpoint(conn, chain)
    if db_block is not None:
        write_json_checkpoint(json_path, db_block)
        return db_block + 1

    # 2) JSON fallback
    json_block = load_json_checkpoint(json_path)
    if json_block is not None:
        write_db_checkpoint(conn, chain, json_block)
        return json_block + 1

    # 3) YAML fallback
    write_db_checkpoint(conn, chain, yaml_start_block)
    write_json_checkpoint(json_path, yaml_start_block)
    return yaml_start_block + 1


# ============================================================
# Batch commit hook (DB → JSON)
# ============================================================
def on_batch_committed(conn, chain: str, last_block: int, json_path: Path) -> None:
    """
    After a batch is fully committed to DB, update:

        - DB canonical checkpoint
        - JSON mirror

    This is called by BaseIndexerService via checkpoint.save().
    """
    write_db_checkpoint(conn, chain, last_block)
    write_json_checkpoint(json_path, last_block)
