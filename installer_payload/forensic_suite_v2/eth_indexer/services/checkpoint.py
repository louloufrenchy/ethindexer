from __future__ import annotations

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

        self.dir_path = Path(r"C:\forensic_state\eth")
        self.dir_path.mkdir(parents=True, exist_ok=True)
        self.path = self.dir_path / "eth_checkpoint.json"

        pg = config.postgres
        self.conn = psycopg2.connect(
            host=pg.host,
            port=pg.port,
            user=pg.user,
            password=pg.password,
            dbname=pg.database,
        )

    async def load(self) -> int:
        db_value = load_db_checkpoint(self.conn, self.chain)
        if db_value is not None:
            self._write_json(db_value)
            return int(db_value)

        if self.path.exists():
            try:
                data = json.loads(self.path.read_text(encoding="utf-8"))
                json_value = int(data.get("last_block", 0))
                write_db_checkpoint(self.conn, self.chain, json_value)
                return json_value
            except Exception:
                pass

        start_block = int(getattr(self.config, "start_block", 0) or 0)
        write_db_checkpoint(self.conn, self.chain, start_block)
        self._write_json(start_block)
        return start_block

    async def save(self, height: int) -> None:
        write_db_checkpoint(self.conn, self.chain, int(height))
        self._write_json(int(height))
        await asyncio.sleep(0)

    def _write_json(self, height: int) -> None:
        data = {"last_block": int(height)}
        self.path.write_text(json.dumps(data), encoding="utf-8")
