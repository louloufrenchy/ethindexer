from __future__ import annotations
import os
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional
import asyncpg
import yaml
from .models import ChainSnapshot, ClusterSummary

CHAINS = ["btc", "eth", "tron"]
log = logging.getLogger("dashboard_service")

class DashboardDataService:
    def __init__(self, config_path: Optional[str] = None) -> None:
        self.config_path = Path(config_path) if config_path else Path(os.environ.get("DASHBOARD_CONFIG_PATH", ""))
        self.pool: Optional[asyncpg.Pool] = None

    def build_dsn(self) -> str:
        with open(self.config_path, "r") as f:
            cfg = yaml.safe_load(f)
        pg = cfg["postgres"]
        return f"postgresql://{pg['user']}:{pg['password']}@{pg['host']}:{pg['port']}/{pg['database']}"

    async def connect(self) -> None:
        if self.pool is None:
            self.pool = await asyncpg.create_pool(self.build_dsn(), min_size=1, max_size=4)

    async def close(self) -> None:
        if self.pool:
            await self.pool.close()

    async def get_bpm_history(self, chain: str) -> dict[str, Any]:
        """REQUIRED METHOD: Fetches BPM trends for charts."""
        tbl = f"{chain}_blocks"
        query = f"""
            SELECT to_char(date_trunc('minute', ts) - (CAST(extract(minute from ts) AS integer) % 5) * interval '1 minute', 'HH24:MI') as bucket,
                   COUNT(*) / 5.0 as bpm
            FROM {tbl} WHERE ts > NOW() - INTERVAL '1 hour'
            GROUP BY bucket ORDER BY bucket ASC
        """
        async with self.pool.acquire() as conn:
            try:
                rows = await conn.fetch(query)
                return {"labels": [r["bucket"] for r in rows], "values": [float(r["bpm"]) for r in rows]}
            except Exception as e:
                log.error(f"Chart query error for {chain}: {e}")
                return {"labels": [], "values": []}

    async def get_recent_transactions(self, chain: str, limit: int = 5) -> list[dict]:
        tbl = f"{chain}_transactions"
        query = f"SELECT tx_hash as display_hash, block_number, ts FROM {tbl} ORDER BY block_number DESC LIMIT $1"
        async with self.pool.acquire() as conn:
            try:
                rows = await conn.fetch(query, limit)
                return [dict(r) for r in rows]
            except Exception: return []

    async def get_recent_transfers(self, chain: str, limit: int = 5) -> list[dict]:
        if chain == "eth":
            query = "SELECT tx_hash as txid, from_address, to_address, amount_raw FROM erc20_transfers ORDER BY block_number DESC LIMIT $1"
        elif chain == "tron":
            query = "SELECT txid, from_address, to_address, amount_raw FROM trc20_transfers ORDER BY block_number DESC LIMIT $1"
        elif chain == "btc":
            query = "SELECT txid, 'UTXO_INPUT' as from_address, address as to_address, amount_sats::text as amount_raw FROM btc_utxos ORDER BY id DESC LIMIT $1"
        else: return []
        async with self.pool.acquire() as conn:
            try:
                rows = await conn.fetch(query, limit)
                return [{"txid": r["txid"], "from_address": r["from_address"] or "N/A",
                         "to_address": r["to_address"] or "N/A", "amount_raw": r["amount_raw"]} for r in rows]
            except Exception: return []

    async def get_high_value_alerts(self) -> list[dict]:
        """Scans for transfers exceeding ~$100k USD in the last hour."""
        alerts = []
        async with self.pool.acquire() as conn:
            # BTC High Value (> 1.5 BTC)
            btc = await conn.fetch("SELECT 'btc' as chain, txid, amount_sats::text as amt, ts FROM btc_utxos WHERE ts > NOW() - INTERVAL '1 hour' AND amount_sats > 150000000 LIMIT 3")
            # ETH High Value
            eth = await conn.fetch("SELECT 'eth' as chain, tx_hash as txid, amount_raw as amt, ts FROM erc20_transfers WHERE ts > NOW() - INTERVAL '1 hour' AND length(amount_raw) > 20 LIMIT 3")
            # TRON High Value
            tron = await conn.fetch("SELECT 'tron' as chain, txid, amount_raw as amt, ts FROM trc20_transfers WHERE ts > NOW() - INTERVAL '1 hour' AND amount_raw::numeric > 1000000000000 LIMIT 3")
            for batch in [btc, eth, tron]:
                alerts.extend([dict(r) for r in batch])
        return sorted(alerts, key=lambda x: x['ts'], reverse=True)

    async def get_log_alerts(self, limit: int = 10) -> list[dict]:
        """Fixed for CLI compatibility: provides 'lag', 'db_queue_depth', and 'mode'."""
        async with self.pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT
                    chain,
                    'STALL' as mode,
                    0 as lag,
                    0 as db_queue_depth,
                    updated_at as ts
                FROM index_checkpoint
                WHERE updated_at < NOW() - INTERVAL '2 minutes'
                ORDER BY updated_at DESC LIMIT $1
            """, limit)
            return [dict(r) for r in rows]

    async def get_cluster_summary(self) -> ClusterSummary:
        snapshots = []
        async with self.pool.acquire() as conn:
            for chain in CHAINS:
                cp = await conn.fetchrow("SELECT last_block, updated_at FROM index_checkpoint WHERE chain=$1", chain)
                tbl_blocks = f"{chain}_blocks"
                count_res = await conn.fetchrow(f"SELECT count(*) as total FROM {tbl_blocks}")
                recent_res = await conn.fetchrow(f"SELECT count(*) as recent FROM {tbl_blocks} WHERE ts > NOW() - INTERVAL '5 minutes'")
                extra_label = "ERC20" if chain == "eth" else "TRC20" if chain == "tron" else "UTXOs"
                extra_tbl = "erc20_transfers" if chain == "eth" else "trc20_transfers" if chain == "tron" else "btc_utxos"
                extra_res = await conn.fetchrow(f"SELECT count(*) as total FROM {extra_tbl}")

                last_block = cp["last_block"] if cp else None
                updated_at = cp["updated_at"] if cp else None
                bpm = (recent_res["recent"] / 5.0) if recent_res else 0.0
                age = int((datetime.now(timezone.utc) - updated_at.replace(tzinfo=timezone.utc)).total_seconds()) if updated_at else 0
                status = "SYNCING" if bpm > 0 else "IDLE"
                if age > 120: status = "STALLED"

                snapshots.append(ChainSnapshot(chain=chain, last_block=last_block, chain_head=None, lag=None, updated_at=updated_at,
                    blocks_count=count_res["total"] if count_res else 0, tx_count=0, extra_count=extra_res["total"] if extra_res else 0,
                    extra_label=extra_label, status=status, health_score=100 if status=="SYNCING" else 50, blocks_per_min=bpm, age_seconds=age,
                    alerts=[f"BPM: {bpm:.2f}"]))
        return ClusterSummary(generated_at=datetime.now(timezone.utc), snapshots=snapshots)
