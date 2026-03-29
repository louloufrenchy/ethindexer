from dataclasses import dataclass
from typing import Any, List

import aiohttp


@dataclass
class BtcBlock:
    height: int
    txids: List[str]


class BtcBlockScanner:
    def __init__(self, config: Any):
        self.config = config
        self.endpoints = [
            ep.rstrip("/")
            for ep in [getattr(config, "endpoint_1", None), getattr(config, "endpoint_2", None)]
            if ep
        ]
        if not self.endpoints:
            raise RuntimeError("BTC config requires endpoint_1 or endpoint_2")

        self.timeout = getattr(config, "timeout", 30)
        self.max_retries = getattr(config, "max_retries", 5)

    async def _rpc(self, method: str, params: list[Any]) -> Any:
        timeout = aiohttp.ClientTimeout(total=self.timeout)
        last_error: Exception | None = None

        for _ in range(self.max_retries):
            for endpoint in self.endpoints:
                try:
                    async with aiohttp.ClientSession(timeout=timeout) as session:
                        payload = {
                            "jsonrpc": "1.0",
                            "id": "btc",
                            "method": method,
                            "params": params,
                        }
                        async with session.post(endpoint, json=payload) as resp:
                            resp.raise_for_status()
                            data = await resp.json()

                    if data.get("error"):
                        raise RuntimeError(f"BTC RPC error for {method}: {data['error']}")

                    return data["result"]
                except Exception as exc:  # noqa: BLE001
                    last_error = exc

        raise RuntimeError(f"BTC RPC failed for {method}: {last_error}")

    async def fetch(self, height: int) -> BtcBlock:
        block_hash = await self._rpc("getblockhash", [height])
        block = await self._rpc("getblock", [block_hash, 2])
        txids = [tx["txid"] for tx in block.get("tx", []) if "txid" in tx]
        return BtcBlock(height=height, txids=txids)

    async def get_chain_head(self) -> int:
        result = await self._rpc("getblockcount", [])
        return int(result)
