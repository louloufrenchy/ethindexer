from pathlib import Path
import json
import asyncio
from typing import Any


class TronCheckpoint:
    def __init__(self, config: Any = None):
        self.dir_path = Path(r"C:\forensic_state\tron")
        self.dir_path.mkdir(parents=True, exist_ok=True)
        self.path = self.dir_path / "tron_checkpoint.json"

    async def load(self) -> int:
        if not self.path.exists():
            return 0
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return int(data.get("last_block", 0))
        except Exception:
            return 0

    async def save(self, height: int) -> None:
        self.dir_path.mkdir(parents=True, exist_ok=True)
        data = {"last_block": int(height)}
        self.path.write_text(json.dumps(data), encoding="utf-8")
        await asyncio.sleep(0)