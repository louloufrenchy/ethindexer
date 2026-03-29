from __future__ import annotations

from collections import defaultdict
from typing import Iterable

from .models import TraceEdge, TraceNode


def merge_parallel_edges(edges: Iterable[TraceEdge]) -> list[TraceEdge]:
    merged: dict[tuple, TraceEdge] = {}
    for edge in edges:
        key = (
            edge.source,
            edge.target,
            edge.kind,
            edge.chain,
            edge.direction,
            edge.contract_address,
        )
        if key not in merged:
            merged[key] = edge
            continue

        current = merged[key]
        current.weight += edge.weight
        if current.txid is None:
            current.txid = edge.txid
        if current.amount_raw is None:
            current.amount_raw = edge.amount_raw
        if current.block_number is None or (
            edge.block_number is not None and edge.block_number > current.block_number
        ):
            current.block_number = edge.block_number
        if current.ts is None or (edge.ts is not None and edge.ts > current.ts):
            current.ts = edge.ts
    return list(merged.values())


def node_degree(nodes: Iterable[TraceNode], edges: Iterable[TraceEdge]) -> dict[str, int]:
    degree = defaultdict(int)
    for edge in edges:
        degree[edge.source] += 1
        degree[edge.target] += 1
    return dict(degree)
