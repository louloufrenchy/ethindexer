from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class TraceQuery:
    address: str
    chain: Optional[str] = None
    max_depth: int = 2
    max_nodes: int = 250
    max_edges: int = 500
    tx_limit_per_address: int = 150
    counterpart_limit_per_tx: int = 40


@dataclass
class TraceNode:
    id: str
    kind: str
    label: str
    chain: Optional[str] = None
    depth: int = 0
    tx_count: int = 0
    first_seen: Optional[datetime] = None
    last_seen: Optional[datetime] = None
    attributes: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        d = asdict(self)
        if self.first_seen is not None:
            d["first_seen"] = self.first_seen.isoformat()
        if self.last_seen is not None:
            d["last_seen"] = self.last_seen.isoformat()
        return d


@dataclass
class TraceEdge:
    id: str
    source: str
    target: str
    kind: str
    chain: Optional[str] = None
    txid: Optional[str] = None
    direction: Optional[str] = None
    contract_address: Optional[str] = None
    amount_raw: Optional[str] = None
    block_number: Optional[int] = None
    ts: Optional[datetime] = None
    weight: int = 1
    attributes: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        d = asdict(self)
        if self.ts is not None:
            d["ts"] = self.ts.isoformat()
        return d


@dataclass
class TraceAlert:
    code: str
    severity: str
    message: str
    context: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class TraceResult:
    query: TraceQuery
    nodes: list[TraceNode]
    edges: list[TraceEdge]
    alerts: list[TraceAlert]
    stats: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "query": asdict(self.query),
            "nodes": [n.to_dict() for n in self.nodes],
            "edges": [e.to_dict() for e in self.edges],
            "alerts": [a.to_dict() for a in self.alerts],
            "stats": self.stats,
        }
