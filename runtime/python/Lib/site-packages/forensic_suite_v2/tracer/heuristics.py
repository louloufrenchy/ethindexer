# forensic_suite_v2/tracer/heuristics.py

from __future__ import annotations
from collections import Counter, defaultdict
from .graph import node_degree
from .models import TraceAlert, TraceEdge, TraceNode, TraceQuery

def build_alerts(nodes: list[TraceNode], edges: list[TraceEdge], query: TraceQuery) -> list[TraceAlert]:
    alerts: list[TraceAlert] = []
    degree = node_degree(nodes, edges)

    # Track paths for loop and peel detection
    address_adj = defaultdict(list)
    for e in edges:
        address_adj[e.source].append(e.target)

    for node in nodes:
        d = degree.get(node.id, 0)

        # 1. Entity Tagging: Exchanges/Miners (High Fan-out)
        if node.kind == "address" and d >= 50:
            node.attributes["entity_type"] = "EXCHANGE_OR_POOL"
            alerts.append(TraceAlert("ENTITY_IDENTIFIED", "medium", f"High-volume hub detected: {node.label[:10]}..."))

        # 2. Laundering: Peel Chain Detection
        # Pattern: One input, one small output, one large "change" output
        if node.kind == "transaction":
            outs = [e for e in edges if e.source == node.id]
            if len(outs) >= 2:
                amounts = [float(e.amount_raw or 0) for e in outs]
                if max(amounts) > sum(amounts) * 0.8: # One massive change output
                    node.attributes["pattern"] = "PEEL_CHAIN"
                    alerts.append(TraceAlert("LAUNDERING_PATTERN", "high", "Peel chain (change-splitting) detected"))

        # 3. Laundering: Loop Detection
        if node.kind == "address" and _has_cycle(node.id, address_adj):
            node.attributes["pattern"] = "CIRCULAR_FLOW"
            alerts.append(TraceAlert("SUSPICIOUS_LOOP", "high", f"Circular money flow detected through {node.label[:10]}"))

        # 4. Dead-End Wallet Detection
        if node.kind == "address" and d == 1 and node.depth == query.max_depth:
            node.attributes["entity_type"] = "DEAD_END"
            node.attributes["is_tail"] = True

    return alerts

def _has_cycle(start_node, adj, visited=None, stack=None):
    if visited is None: visited = set()
    if stack is None: stack = set()
    visited.add(start_node)
    stack.add(start_node)
    for neighbor in adj.get(start_node, []):
        if neighbor not in visited:
            if _has_cycle(neighbor, adj, visited, stack): return True
        elif neighbor in stack: return True
    stack.remove(start_node)
    return False
