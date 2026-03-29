from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Optional

import asyncpg


class TronCheckpoint:
    chain_name = "tron"

    def __init__(self, config: Any):
        self.config = config
        self.state_dir = Path(r"C:\forensic_state\tron")
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.file_path = self.state_dir / "tron_checkpoint.json"
        self._pool: asyncpg.Pool | None = None

    async def _ensure_pool(self) -> asyncpg.Pool:
        if self._pool is None:
            pg = self.config.postgres
            dsn = f"postgresql://{pg.user}:{pg.password}@{pg.host}:{pg.port}/{pg.database}"
            self._pool = await asyncpg.create_pool(dsn=dsn, min_size=1, max_size=2)
        return self._pool

    async def load(self) -> int:
        db_value = await self._load_from_db()
        if db_value is not None:
            return db_value

        file_value = self._load_from_file()
        if file_value is not None:
            return file_value

        return self._start_block_from_config()

    async def save(self, last_block: int) -> None:
        height = int(last_block)
        await self._save_to_db(height)
        self._save_to_file(height)

    async def reset(self) -> int:
        """
        Reset runtime checkpoint state for this chain and return the configured YAML start_block.
        """
        await self._delete_from_db()
        self._delete_file()
        return self._start_block_from_config()

    async def _load_from_db(self) -> Optional[int]:
        pool = await self._ensure_pool()
        async with pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT last_block
                FROM index_checkpoint
                WHERE chain = $1
                ORDER BY updated_at DESC NULLS LAST, id DESC NULLS LAST
                LIMIT 1
                """,
                self.chain_name,
            )

        if not row:
            return None

        try:
            return int(row["last_block"])
        except Exception:
            return None

    async def _save_to_db(self, last_block: int) -> None:
        pool = await self._ensure_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO index_checkpoint (chain, last_block, updated_at)
                VALUES ($1, $2, NOW())
                ON CONFLICT (chain)
                DO UPDATE SET
                    last_block = EXCLUDED.last_block,
                    updated_at = EXCLUDED.updated_at
                """,
                self.chain_name,
                int(last_block),
            )

    async def _delete_from_db(self) -> None:
        pool = await self._ensure_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                "DELETE FROM index_checkpoint WHERE chain = $1",
                self.chain_name,
            )

    def _load_from_file(self) -> Optional[int]:
        if not self.file_path.exists():
            return None

        try:
            payload = json.loads(self.file_path.read_text(encoding="utf-8"))
        except Exception:
            return None

        try:
            return int(payload["last_block"])
        except Exception:
            return None

    def _save_to_file(self, last_block: int) -> None:
        payload = {"last_block": int(last_block)}
        self.file_path.write_text(
            json.dumps(payload, separators=(",", ":")),
            encoding="utf-8",
        )

    def _delete_file(self) -> None:
        try:
            if self.file_path.exists():
                self.file_path.unlink()
        except Exception:
            pass

    def _start_block_from_config(self) -> int:
        value = getattr(self.config, "start_block", 0)
        try:
            return int(value)
        except Exception:
            return 0
