from dataclasses import dataclass
from typing import Any, List

import aiohttp


from dataclasses import dataclass
from typing import List, Optional


@dataclass
class TronBlock:
    block_number: int
    block_hash: Optional[str]
    timestamp_ms: Optional[int]
    txids: List[str]

class TronBlockScanner:
    def __init__(self, config: Any):
        self.config = config
        self.endpoints = [
            ep.rstrip("/")
            for ep in [getattr(config, "endpoint_1", None), getattr(config, "endpoint_2", None)]
            if ep
        ]
        if not self.endpoints:
            raise RuntimeError("TRON config requires endpoint_1 or endpoint_2")

        self.timeout = getattr(config, "timeout", 30)
        self.max_retries = getattr(config, "max_retries", 5)

    async def _post_json(self, path: str, payload: dict | None = None) -> Any:
        timeout = aiohttp.ClientTimeout(total=self.timeout)
        last_error: Exception | None = None

        for _ in range(self.max_retries):
            for endpoint in self.endpoints:
                try:
                    async with aiohttp.ClientSession(timeout=timeout) as session:
                        url = f"{endpoint}{path}"
                        async with session.post(url, json=payload or {}) as resp:
                            resp.raise_for_status()
                            return await resp.json()
                except Exception as exc:  # noqa: BLE001
                    last_error = exc

        raise RuntimeError(f"TRON RPC failed for {path}: {last_error}")

    async def fetch(self, height: int) -> TronBlock:
        data = await self._post_json("/wallet/getblockbynum", {"num": height})

        if not data:
            raise RuntimeError(f"[TRON] Failed to fetch block {height}")

        block_hash = data.get("blockID")

        timestamp_ms = (
            data.get("block_header", {})
            .get("raw_data", {})
            .get("timestamp")
        )

        txids = [
            tx.get("txID")
            for tx in data.get("transactions", []) or []
            if tx.get("txID")
        ]

        return TronBlock(
            block_number=height,
            block_hash=block_hash,
            timestamp_ms=timestamp_ms,
            txids=txids,
        )

    async def get_chain_head(self) -> int:
        data = await self._post_json("/wallet/getnowblock")
        return int(data["block_header"]["raw_data"]["number"])
