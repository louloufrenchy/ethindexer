from dataclasses import dataclass
from typing import Any, List

import aiohttp


@dataclass
class EthBlock:
    height: int
    txids: List[str]


class EthBlockScanner:
    def __init__(self, config: Any):
        self.config = config
        self.http_endpoint = config.http_endpoint.rstrip("/")
        self.timeout = getattr(config, "timeout", 30)
        self.max_retries = getattr(config, "max_retries", 5)

    async def _rpc(self, method: str, params: list[Any]) -> Any:
        timeout = aiohttp.ClientTimeout(total=self.timeout)
        last_error: Exception | None = None

        for _ in range(self.max_retries):
            try:
                async with aiohttp.ClientSession(timeout=timeout) as session:
                    payload = {
                        "jsonrpc": "2.0",
                        "method": method,
                        "params": params,
                        "id": 1,
                    }
                    async with session.post(self.http_endpoint, json=payload) as resp:
                        resp.raise_for_status()
                        data = await resp.json()

                if data.get("error"):
                    raise RuntimeError(f"ETH RPC error for {method}: {data['error']}")

                return data["result"]
            except Exception as exc:  # noqa: BLE001
                last_error = exc

        raise RuntimeError(f"ETH RPC failed for {method}: {last_error}")

    async def fetch(self, height: int) -> EthBlock:
        block = await self._rpc("eth_getBlockByNumber", [hex(height), True])
        if not block:
            raise RuntimeError(f"ETH block not found at height {height}")

        txids = [tx["hash"] for tx in block.get("transactions", []) if "hash" in tx]
        return EthBlock(height=height, txids=txids)

    async def get_chain_head(self) -> int:
        result = await self._rpc("eth_blockNumber", [])
        return int(result, 16)
