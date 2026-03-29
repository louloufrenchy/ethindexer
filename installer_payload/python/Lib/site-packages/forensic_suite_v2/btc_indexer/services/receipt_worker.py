from __future__ import annotations

import asyncio
from typing import Any, Optional

import aiohttp
import logging

log = logging.getLogger("btc_receipt_worker")


class BtcReceiptWorker:
    """
    BTC transaction fetch worker for block-first ingestion.

    The shared indexer_engine now passes:
    - txid
    - block_number
    - block_hash

    BTC must use those as authoritative values because getrawtransaction(...)
    does not reliably return blockheight/block_number on all nodes/providers.
    """

    def __init__(self, config: Any, queue: asyncio.Queue):
        self.config = config
        self.queue = queue

        self.endpoints = [
            ep.rstrip("/")
            for ep in [getattr(config, "endpoint_1", None), getattr(config, "endpoint_2", None)]
            if ep
        ]
        if not self.endpoints:
            raise RuntimeError("BTC config requires endpoint_1 or endpoint_2")

        self.timeout = int(getattr(config, "timeout", 30))
        self.max_retries = int(getattr(config, "max_retries", 5))
        self.retry_delay = float(getattr(config, "retry_delay", 1.0))
        self.semaphore = asyncio.Semaphore(int(getattr(config, "receipt_concurrency", 10)))

        self._endpoint_index = 0

    async def submit(
        self,
        txid: str,
        block_number: int | None = None,
        block_hash: str | None = None,
    ) -> None:
        async with self.semaphore:
            tx = await self._fetch_tx(txid)

            if tx is not None:
                if block_number is not None:
                    tx["block_number"] = block_number
                    tx["block_height"] = block_number

                if block_hash:
                    tx["block_hash"] = block_hash

                await self.queue.put(tx)

            await asyncio.sleep(0)

    async def _rpc(self, method: str, params: list[Any]) -> Any:
        timeout = aiohttp.ClientTimeout(total=self.timeout)
        last_error: Exception | None = None

        payload = {
            "jsonrpc": "1.0",
            "id": "btc",
            "method": method,
            "params": params,
        }

        for _ in range(self.max_retries):
            for _ in range(len(self.endpoints)):
                endpoint = self.endpoints[self._endpoint_index % len(self.endpoints)]
                self._endpoint_index += 1

                try:
                    async with aiohttp.ClientSession(timeout=timeout) as session:
                        async with session.post(endpoint, json=payload) as resp:
                            resp.raise_for_status()
                            data = await resp.json()

                    if data.get("error"):
                        raise RuntimeError(f"BTC RPC error for {method}: {data['error']}")

                    return data.get("result")

                except asyncio.CancelledError:
                    raise

                except Exception as exc:  # noqa: BLE001
                    last_error = exc
                    log.warning("[BTC] request failed endpoint=%s method=%s err=%s", endpoint, method, exc)

            await asyncio.sleep(self.retry_delay)

        log.error("[BTC] RPC failed method=%s params=%s err=%s", method, params, last_error)
        return None

    async def _fetch_tx(self, txid: str) -> Optional[dict]:
        tx = await self._rpc("getrawtransaction", [txid, True])
        if not tx:
            log.warning("[BTC] getrawtransaction missing tx for txid=%s", txid)
            return None

        return self._normalize_tx(tx)

    def _normalize_tx(self, tx: dict) -> Optional[dict]:
        if not tx:
            return None

        block_height = tx.get("height")
        if block_height is None:
            block_height = tx.get("blockheight")

        return {
            "txid": tx.get("txid"),
            "block_hash": tx.get("blockhash"),
            "block_height": block_height,
            "block_number": block_height,
            "timestamp": tx.get("time"),
            "vin": tx.get("vin", []) or [],
            "vout": tx.get("vout", []) or [],
        }
