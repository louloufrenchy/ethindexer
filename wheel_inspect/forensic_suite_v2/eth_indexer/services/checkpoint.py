# forensic_suite_v2/eth_indexer/services/checkpoint.py

from pathlib import Path
import json
import asyncio
from typing import Any
import psycopg2

from forensic_suite_v2.common.db_checkpoints import (
    load_db_checkpoint,
    write_db_checkpoint,
)


class EthCheckpoint:
    def __init__(self, config: Any = None):
        self.chain = "eth"
        self.config = config

        # JSON mirror path
        self.dir_path = Path(r"C:\forensic_state\eth")
        self.dir_path.mkdir(parents=True, exist_ok=True)
        self.path = self.dir_path / "eth_checkpoint.json"

        # DB connection details
        pg = config.postgres
        self.conn = psycopg2.connect(
            host=pg.host,
            port=pg.port,
            user=pg.user,
            password=pg.password,
            dbname=pg.database,
        )

    async def load(self) -> int:
        """
        Load checkpoint from DB first, fallback to JSON.
        """
        db_value = load_db_checkpoint(self.conn, self.chain)
        if db_value is not None:
            self._write_json(db_value)
            return db_value

        if self.path.exists():
            try:
                data = json.loads(self.path.read_text(encoding="utf-8"))
                json_value = int(data.get("last_block", 0))
                write_db_checkpoint(self.conn, self.chain, json_value)
                return json_value
            except Exception:
                return 0

        return 0

    async def save(self, height: int) -> None:
        """
        Save checkpoint to DB (canonical) and JSON (mirror).
        """
        write_db_checkpoint(self.conn, self.chain, height)
        self._write_json(height)
        await asyncio.sleep(0)

    def _write_json(self, height: int) -> None:
        data = {"last_block": int(height)}
        self.path.write_text(json.dumps(data), encoding="utf-8")
