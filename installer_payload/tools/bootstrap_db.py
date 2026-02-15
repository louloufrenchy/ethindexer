import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from pathlib import Path

DB_NAME = "forensic"
DB_USER = "postgres"
DB_PASS = "Str0ngPassw0rd2025"
DB_HOST = "127.0.0.1"

def ensure_database():
    conn = psycopg2.connect(
        dbname="postgres",
        user=DB_USER,
        password=DB_PASS,
        host=DB_HOST
    )
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()

    cur.execute("SELECT 1 FROM pg_database WHERE datname=%s", (DB_NAME,))
    exists = cur.fetchone()

    if not exists:
        cur.execute(f"CREATE DATABASE {DB_NAME}")

    cur.close()
    conn.close()

def apply_sql_file(path: Path):
    if not path.exists():
        return

    sql = path.read_text(encoding="utf-8")

    conn = psycopg2.connect(
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        host=DB_HOST
    )
    cur = conn.cursor()
    cur.execute(sql)
    conn.commit()
    cur.close()
    conn.close()

def main():
    base = Path(__file__).resolve().parent.parent / "db"

    ensure_database()
    apply_sql_file(base / "schema.sql")
    apply_sql_file(base / "views.sql")

if __name__ == "__main__":
    main()
