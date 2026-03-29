from __future__ import annotations
import asyncio
import logging
from typing import Any, Optional
import aiohttp

log = logging.getLogger("eth_receipt_worker")

class EthReceiptWorker:
    def __init__(self, config: Any, queue: asyncio.Queue):
        self.config = config
        self.queue = queue

        # FIX: Support 'http_endpoint' from your YAML or fallback to 'endpoint_1'
        self.endpoint = getattr(config, "http_endpoint", None) or getattr(config, "endpoint_1", None)

        # Safety check to prevent indexer crash on startup
        if not self.endpoint:
            log.error("[ETH] No valid RPC endpoint found in configuration!")

        self.semaphore = asyncio.Semaphore(int(getattr(config, "receipt_concurrency", 20)))

    async def submit(
        self,
        txid: str,
        block_number: int | None = None,
        block_hash: str | None = None,
    ) -> None:
        """Fetch receipt and ensure block context is attached for atomic DB flush."""
        async with self.semaphore:
            receipt = await self.fetch_receipt(txid)
            if receipt:
                # Inject block context provided by the Indexer Engine
                if block_number is not None:
                    receipt["block_number"] = block_number
                if block_hash is not None:
                    receipt["block_hash"] = block_hash

                await self.queue.put(receipt)
            await asyncio.sleep(0)

    async def fetch_receipt(self, txid: str) -> Optional[dict]:
        if not self.endpoint:
            return None

        payload = {
            "jsonrpc": "2.0",
            "method": "eth_getTransactionReceipt",
            "params": [txid],
            "id": 1
        }

        try:
            # Use a single session per request for simplicity in the worker
            async with aiohttp.ClientSession() as session:
                async with session.post(self.endpoint, json=payload, timeout=15) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        if data and "result" in data and data["result"]:
                            return self._parse_receipt(data["result"])
        except Exception as e:
            log.warning(f"[ETH] RPC Error on {self.endpoint}: {e}")
        return None

    def _parse_receipt(self, receipt: dict) -> dict:
        """Standardizes the receipt for the EthDBWriter."""
        txid = receipt.get("transactionHash")
        status_hex = receipt.get("status")

        # Convert hex blockNumber to int if present
        b_num = receipt.get("blockNumber")
        if isinstance(b_num, str) and b_num.startswith("0x"):
            b_num = int(b_num, 16)

        parsed = {
            "txid": txid,
            "block_number": b_num,
            "block_hash": receipt.get("blockHash"),
            "status": "success" if status_hex == "0x1" else "failed",
            "from_address": receipt.get("from"),
            "to_address": receipt.get("to"),
            "gas_used": int(receipt["gasUsed"], 16) if "gasUsed" in receipt else 0,
            "erc20_transfers": self._extract_erc20_events(receipt),
            "timestamp_ms": None, # Populated by engine/db_writer context
        }
        return parsed

    def _extract_erc20_events(self, receipt: dict) -> list[dict]:
        transfers = []
        # ERC20 Transfer(address,address,uint256) signature
        TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

        for idx, log_entry in enumerate(receipt.get("logs", [])):
            topics = log_entry.get("topics", [])
            if len(topics) == 3 and topics[0].lower() == TRANSFER_TOPIC:
                # Standardize block number from receipt context
                b_num = receipt.get("blockNumber")
                if isinstance(b_num, str) and b_num.startswith("0x"):
                    b_num = int(b_num, 16)

                transfers.append({
                    "txid": receipt.get("transactionHash"),
                    "log_index": idx,
                    "contract_address": log_entry.get("address"),
                    "from_address": "0x" + topics[1][-40:],
                    "to_address": "0x" + topics[2][-40:],
                    "amount_raw": str(int(log_entry.get("data", "0x0"), 16)),
                    "block_number": b_num,
                })
        return transfers
