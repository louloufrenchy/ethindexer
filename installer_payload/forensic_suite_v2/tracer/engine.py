# forensic_suite_v2/tracer/engine.py

from __future__ import annotations
from collections import deque
from datetime import datetime
from typing import Optional, List, Dict, Any
import asyncpg

from .graph import merge_parallel_edges
from .heuristics import build_alerts
from .models import TraceEdge, TraceNode, TraceQuery, TraceResult

class TraceEngine:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self.pool = pool

    async def trace(self, query: TraceQuery) -> TraceResult:
        nodes: dict[str, TraceNode] = {}
        edges: list[TraceEdge] = []

        # Queue format: (address, chain, current_depth, is_high_priority)
        queue: deque[tuple[str, Optional[str], int, bool]] = deque()
        queue.append((query.address, query.chain, 0, False))

        visited_addresses = {(query.address.lower(), (query.chain or "").lower() or None)}
        visited_txids = set()

        while queue and len(nodes) < query.max_nodes:
            address, current_chain, depth, is_high_priority = queue.popleft()

            # AUTO-TRACE: High priority nodes get +1 depth buffer
            effective_max = query.max_depth + 1 if is_high_priority else query.max_depth
            if depth >= effective_max:
                continue

            tx_rows = await self._fetch_address_flows(address, current_chain, query.tx_limit_per_address)

            for row in tx_rows:
                txid, row_chain = row["txid"], row["chain"]
                if not txid or txid in visited_txids:
                    continue
                visited_txids.add(txid)

                participants = await self._fetch_tx_participants(txid, row_chain, query.counterpart_limit_per_tx)

                tx_node_id = f"tx:{row_chain}:{txid}"
                if tx_node_id not in nodes:
                    nodes[tx_node_id] = TraceNode(id=tx_node_id, kind="transaction", label=txid, chain=row_chain, depth=depth + 1)

                for p_row in participants:
                    p_addr, p_chain = p_row["address"], p_row["chain"]
                    addr_node_id = self._address_node_id(p_addr, p_chain)

                    if addr_node_id not in nodes:
                        nodes[addr_node_id] = TraceNode(id=addr_node_id, kind="address", label=p_addr, chain=p_chain, depth=depth+1)

                        # Internal risk check to trigger Auto-Trace mid-run
                        # In a real scenario, this would call a subset of heuristics.py
                        is_risky = p_row.get("amount_raw") and len(p_row["amount_raw"]) > 18

                        p_key = (p_addr.lower(), p_chain.lower())
                        if p_key not in visited_addresses:
                            visited_addresses.add(p_key)
                            queue.append((p_addr, None, depth + 1, is_risky))

                    edges.append(TraceEdge(
                        id=f"edge:{addr_node_id}->{tx_node_id}:{p_row['direction']}",
                        source=addr_node_id, target=tx_node_id, kind="address_to_tx",
                        chain=p_chain, txid=txid, direction=p_row["direction"],
                        amount_raw=p_row["amount_raw"], ts=p_row["ts"]
                    ))

        self._hydrate_node_stats(nodes, edges)
        merged = merge_parallel_edges(edges)
        alerts = build_alerts(list(nodes.values()), merged, query)

        return TraceResult(
            query=query, nodes=list(nodes.values()), edges=merged, alerts=alerts,
            stats={"nodes": len(nodes), "edges": len(merged), "txs": len(visited_txids)}
        )

    async def _fetch_address_flows(self, address: str, chain: Optional[str], limit: int):
        sql = "SELECT * FROM v_all_flows WHERE address = $1"
        args = [address.lower()]
        if chain:
            sql += " AND chain = $2"
            args.append(chain.lower())
        sql += " ORDER BY ts DESC LIMIT $" + str(len(args) + 1)
        args.append(limit)
        async with self.pool.acquire() as conn: return await conn.fetch(sql, *args)

    async def _fetch_tx_participants(self, txid: str, chain: str, limit: int):
        sql = "SELECT * FROM v_all_flows WHERE txid = $1 AND chain = $2 LIMIT $3"
        async with self.pool.acquire() as conn: return await conn.fetch(sql, txid, chain.lower(), limit)

    def _hydrate_node_stats(self, nodes: dict, edges: list):
        for e in edges:
            for nid in (e.source, e.target):
                if nid in nodes: nodes[nid].tx_count += 1

    @staticmethod
    def _address_node_id(address: str, chain: Optional[str]) -> str:
        return f"addr:{chain or 'global'}:{address.lower()}"
