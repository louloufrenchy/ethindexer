from dataclasses import dataclass
from typing import Any, List

import aiohttp


@dataclass
class TronBlock:
    height: int
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
        txids = [tx["txID"] for tx in data.get("transactions", []) if "txID" in tx]
        return TronBlock(height=height, txids=txids)

    async def get_chain_head(self) -> int:
        data = await self._post_json("/wallet/getnowblock")
        return int(data["block_header"]["raw_data"]["number"])
