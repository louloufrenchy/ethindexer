from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Any, List, Optional

import aiohttp


@dataclass
class EthBlock:
    block_number: int
    block_hash: Optional[str]
    timestamp: Optional[int]
    txs: List[dict]
    txids: List[str]


class EthBlockScanner:
    """
    Ethereum block scanner with a persistent aiohttp ClientSession.

    Returns full block metadata so block-level DB writes can happen before
    tx/receipt processing.
    """

    def __init__(self, config: Any):
        self.config = config
        self.http_endpoint = config.http_endpoint.rstrip("/")

        self.timeout_seconds = getattr(config, "timeout", 30)
        self.max_retries = getattr(config, "max_retries", 5)
        self.retry_delay = getattr(config, "retry_delay", 2)
        self.connector_limit = getattr(config, "connector_limit", 10)

        self._timeout = aiohttp.ClientTimeout(total=self.timeout_seconds)
        self._session: aiohttp.ClientSession | None = None

    async def start(self) -> None:
        if self._session is not None and not self._session.closed:
            return

        connector = aiohttp.TCPConnector(
            limit=self.connector_limit,
            enable_cleanup_closed=True,
            ttl_dns_cache=300,
        )

        self._session = aiohttp.ClientSession(
            timeout=self._timeout,
            connector=connector,
            raise_for_status=False,
        )

    async def close(self) -> None:
        if self._session is not None and not self._session.closed:
            await self._session.close()
        self._session = None

    async def __aenter__(self) -> "EthBlockScanner":
        await self.start()
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        await self.close()

    async def _ensure_session(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            await self.start()

        if self._session is None or self._session.closed:
            raise RuntimeError("ETH RPC session could not be initialized")

        return self._session

    async def _rpc(self, method: str, params: list[Any]) -> Any:
        session = await self._ensure_session()
        last_error: Exception | None = None

        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1,
        }

        for attempt in range(1, self.max_retries + 1):
            try:
                async with session.post(self.http_endpoint, json=payload) as resp:
                    resp.raise_for_status()
                    data = await resp.json()

                if data.get("error"):
                    raise RuntimeError(f"ETH RPC error for {method}: {data['error']}")

                if "result" not in data:
                    raise RuntimeError(f"ETH RPC malformed response for {method}: {data}")

                return data["result"]

            except asyncio.CancelledError:
                raise

            except Exception as exc:  # noqa: BLE001
                last_error = exc

                if self._session is None or self._session.closed:
                    await self.start()
                    session = await self._ensure_session()

                if attempt < self.max_retries:
                    await asyncio.sleep(self.retry_delay)

        raise RuntimeError(f"ETH RPC failed for {method}: {last_error}")

    async def fetch(self, height: int) -> EthBlock:
        block = await self._rpc("eth_getBlockByNumber", [hex(height), True])
        if not block:
            raise RuntimeError(f"ETH block not found at height {height}")

        block_hash = block.get("hash")

        timestamp_hex = block.get("timestamp")
        timestamp = int(timestamp_hex, 16) if timestamp_hex else None

        txs = block.get("transactions", []) or []
        txids = [tx["hash"] for tx in txs if "hash" in tx]

        return EthBlock(
            block_number=height,
            block_hash=block_hash,
            timestamp=timestamp,
            txs=txs,
            txids=txids,
        )

    async def get_chain_head(self) -> int:
        result = await self._rpc("eth_blockNumber", [])
        return int(result, 16)
