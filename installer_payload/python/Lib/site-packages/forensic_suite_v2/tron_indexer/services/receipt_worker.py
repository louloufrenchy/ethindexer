from __future__ import annotations
import asyncio
import logging
from typing import Any, Optional
import aiohttp

log = logging.getLogger("tron_receipt_worker")

# Topic for TRC20 Transfer(address,address,uint256)
TRC20_TRANSFER_TOPIC = "ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

class TronReceiptWorker:
    def __init__(self, config: Any, queue: asyncio.Queue):
        self.config = config
        self.queue = queue
        # Supports both endpoint_1/2 or the consolidated http_endpoint
        self.endpoints = getattr(config, "endpoints", [])
        if not self.endpoints:
            self.endpoints = [getattr(config, "endpoint_1", ""), getattr(config, "endpoint_2", "")]

        # Filter out empty strings
        self.endpoints = [e for e in self.endpoints if e]
        self._endpoint_index = 0
        self.semaphore = asyncio.Semaphore(int(getattr(config, "receipt_concurrency", 10)))

    async def submit(
        self,
        txid: str,
        block_number: int | None = None,
        block_hash: str | None = None,
    ) -> None:
        """Fetch transaction data and attach block context for atomic DB commit."""
        async with self.semaphore:
            tx = await self.fetch_transaction(txid)
            if tx is not None:
                # Prioritize context passed from the Indexer Engine
                if block_number:
                    tx["block_number"] = block_number
                if block_hash:
                    tx["block_hash"] = block_hash

                await self.queue.put(tx)
            await asyncio.sleep(0)

    async def fetch_transaction(self, txid: str) -> Optional[dict]:
        tx = await self._post_json("/wallet/gettransactionbyid", {"value": txid})
        if not tx:
            return None

        # Transaction Info contains logs and block context
        info = await self._post_json("/walletsolidity/gettransactioninfobyid", {"value": txid})
        return self._parse_transaction(tx, info or {})

    async def _post_json(self, path: str, payload: dict) -> Optional[dict]:
        for _ in range(len(self.endpoints)):
            endpoint = self._next_endpoint()
            url = endpoint.rstrip("/") + path
            try:
                timeout = aiohttp.ClientTimeout(total=20)
                async with aiohttp.ClientSession(timeout=timeout) as session:
                    async with session.post(url, json=payload) as resp:
                        if resp.status == 200:
                            return await resp.json(content_type=None)
            except Exception as exc:
                log.warning("[TRON] RPC attempt failed url=%s err=%s", url, exc)
        return None

    def _next_endpoint(self) -> str:
        endpoint = self.endpoints[self._endpoint_index % len(self.endpoints)]
        self._endpoint_index += 1
        return endpoint

    def _parse_transaction(self, tx: dict, info: dict) -> dict:
        txid = tx.get("txID") or tx.get("txid")
        raw_data = tx.get("raw_data", {}) or {}
        contracts = raw_data.get("contract", []) or []

        # TRON internal block hash is 'blockID'
        block_number = info.get("blockNumber")
        block_hash = info.get("blockID") or info.get("blockHash")

        timestamp_ms = info.get("blockTimeStamp") or raw_data.get("timestamp") or tx.get("timestamp")

        parsed = {
            "txid": txid,
            "block_number": self._to_int(block_number),
            "block_hash": block_hash,
            "timestamp_ms": self._to_int(timestamp_ms),
            "status": self._status_from_info(info),
            "from_address": None,
            "to_address": None,
            "amount_raw": "0",
            "contract_address": None,
            "extra_transfers": [],
            "trc20_transfers": [],
        }

        for contract in contracts:
            ctype = contract.get("type")
            param = ((contract.get("parameter") or {}).get("value")) or {}

            if ctype == "TransferContract":
                parsed["from_address"] = self._normalize_address(param.get("owner_address"))
                parsed["to_address"] = self._normalize_address(param.get("to_address"))
                parsed["amount_raw"] = self._stringify_numeric(param.get("amount"))
                parsed["contract_address"] = "TRX"
            elif ctype == "TriggerSmartContract":
                parsed["from_address"] = self._normalize_address(param.get("owner_address"))
                parsed["contract_address"] = self._normalize_address(param.get("contract_address"))
            elif ctype == "TransferAssetContract":
                parsed["extra_transfers"].append({
                    "from_address": self._normalize_address(param.get("owner_address")),
                    "to_address": self._normalize_address(param.get("to_address")),
                    "amount": self._stringify_numeric(param.get("amount")),
                    "contract_address": self._normalize_asset_name(param.get("asset_name")),
                })

        parsed["trc20_transfers"] = self._extract_trc20_transfers(txid, parsed["block_number"], parsed["timestamp_ms"], info)
        return parsed

    def _extract_trc20_transfers(self, txid, block_number, timestamp_ms, info) -> list[dict]:
        out = []
        for idx, log_entry in enumerate(info.get("log", []) or []):
            topics = log_entry.get("topics") or []
            if len(topics) < 3 or self._normalize_hex(topics[0]) != TRC20_TRANSFER_TOPIC:
                continue

            out.append({
                "txid": txid,
                "log_index": idx,
                "contract_address": self._normalize_address(log_entry.get("address")),
                "from_address": self._tron_address_from_topic(topics[1]),
                "to_address": self._tron_address_from_topic(topics[2]),
                "amount_raw": self._hex_to_decimal_string(log_entry.get("data")),
                "block_number": block_number,
                "timestamp_ms": timestamp_ms,
            })
        return out

    @staticmethod
    def _normalize_asset_name(value: Any) -> str:
        """Fixes previous AttributeError by handling TRC10 asset names."""
        if not value: return "UNKNOWN"
        if isinstance(value, bytes):
            try: return value.decode('utf-8')
            except: return value.hex()
        return str(value)

    @staticmethod
    def _status_from_info(info: dict) -> str:
        res = (info.get("receipt") or {}).get("result")
        if res: return str(res).lower()
        return "success" if info.get("result") != "FAILED" else "failed"

    @staticmethod
    def _normalize_address(value: Any) -> Optional[str]:
        if not value: return None
        h = value.hex() if isinstance(value, bytes) else str(value).strip().replace("0x", "")
        if len(h) == 40: h = "41" + h
        return h.lower() if len(h) == 42 else None

    @staticmethod
    def _tron_address_from_topic(topic: Any) -> Optional[str]:
        if not topic: return None
        h = str(topic).strip().lower().replace("0x", "")
        return ("41" + h[-40:]) if len(h) >= 40 else None

    @staticmethod
    def _normalize_hex(v: Any) -> str:
        s = str(v).strip().lower()
        return s[2:] if s.startswith("0x") else s

    @staticmethod
    def _hex_to_decimal_string(v: Any) -> str:
        if not v: return "0"
        s = str(v).strip().lower().replace("0x", "")
        try: return str(int(s, 16))
        except: return "0"

    @staticmethod
    def _to_int(v: Any) -> Optional[int]:
        if v is None: return None
        try: return int(v, 16) if isinstance(v, str) and v.startswith("0x") else int(v)
        except: return None

    @staticmethod
    def _stringify_numeric(v: Any) -> str:
        if v is None: return "0"
        return str(int(v))
