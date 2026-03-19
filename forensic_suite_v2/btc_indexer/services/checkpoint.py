<<<<<<< HEAD
=======
# forensic_suite_v2/btc_indexer/services/checkpoint.py
>>>>>>> master
from pathlib import Path
import json
import asyncio
from typing import Any


class BtcCheckpoint:
    def __init__(self, config: Any = None):
<<<<<<< HEAD
        base = Path(__file__).resolve().parents[1]
        self.path = base / "btc_checkpoint.json"
=======
        self.dir_path = Path(r"C:\forensic_state\btc")
        self.dir_path.mkdir(parents=True, exist_ok=True)
        self.path = self.dir_path / "btc_checkpoint.json"
>>>>>>> master

    async def load(self) -> int:
        if not self.path.exists():
            return 0
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return int(data.get("last_block", 0))
        except Exception:
            return 0

    async def save(self, height: int) -> None:
<<<<<<< HEAD
        data = {"last_block": int(height)}
        self.path.write_text(json.dumps(data), encoding="utf-8")
        await asyncio.sleep(0)
=======
        self.dir_path.mkdir(parents=True, exist_ok=True)
        data = {"last_block": int(height)}
        self.path.write_text(json.dumps(data), encoding="utf-8")
        await asyncio.sleep(0)
>>>>>>> master
