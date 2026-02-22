from pathlib import Path
import json
import asyncio
from typing import Any


class EthCheckpoint:
    def __init__(self, config: Any = None):
        base = Path(__file__).resolve().parents[1]
        self.path = base / "eth_checkpoint.json"

    async def load(self) -> int:
        if not self.path.exists():
            return 0
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return int(data.get("last_block", 0))
        except Exception:
            return 0

    async def save(self, height: int) -> None:
        data = {"last_block": int(height)}
        self.path.write_text(json.dumps(data), encoding="utf-8")
        await asyncio.sleep(0)
