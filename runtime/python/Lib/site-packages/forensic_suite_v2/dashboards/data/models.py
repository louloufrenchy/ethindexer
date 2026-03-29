from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class ChainSnapshot:
    chain: str
    last_block: Optional[int]
    chain_head: Optional[int]
    lag: Optional[int]
    updated_at: Optional[datetime]
    blocks_count: int
    tx_count: int
    extra_count: int
    extra_label: str
    status: str
    health_score: int
    blocks_per_min: Optional[float]
    age_seconds: Optional[int]
    alerts: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        data = asdict(self)
        if self.updated_at is not None:
            data["updated_at"] = self.updated_at.isoformat()
        return data


@dataclass
class ClusterSummary:
    generated_at: datetime
    snapshots: list[ChainSnapshot]

    def to_dict(self) -> dict:
        return {"generated_at": self.generated_at.isoformat(), "snapshots": [s.to_dict() for s in self.snapshots]}


@dataclass
class TraceQuery:
    address: str
    chain: Optional[str] = None
    limit: int = 250


@dataclass
class TraceRow:
    chain: str
    address: str
    txid: str
    direction: str
    contract_address: Optional[str]
    amount_raw: Optional[str]
    block_number: Optional[int]
    ts: Optional[datetime]

    def to_dict(self) -> dict:
        return {
            "chain": self.chain,
            "address": self.address,
            "txid": self.txid,
            "direction": self.direction,
            "contract_address": self.contract_address,
            "amount_raw": self.amount_raw,
            "block_number": self.block_number,
            "ts": self.ts.isoformat() if self.ts else None,
        }
