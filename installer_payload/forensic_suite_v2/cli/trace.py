# forensic_suite_v2/cli/trace.py

from __future__ import annotations

import argparse
import asyncio
import json

from forensic_suite_v2.dashboards.data import DashboardDataService
from forensic_suite_v2.tracer import TraceEngine, TraceQuery, to_cytoscape_elements


async def run(args) -> None:
    service = DashboardDataService()
    await service.connect()
    try:
        engine = TraceEngine(service.pool)
        result = await engine.trace(
            TraceQuery(
                address=args.address,
                chain=args.chain,
                max_depth=args.max_depth,
                max_nodes=args.max_nodes,
                max_edges=args.max_edges,
                tx_limit_per_address=args.tx_limit_per_address,
                counterpart_limit_per_tx=args.counterpart_limit_per_tx,
            )
        )

        if args.format == "json":
            print(json.dumps(result.to_dict(), indent=2))
        elif args.format == "cytoscape":
            print(json.dumps({"elements": to_cytoscape_elements(result), "stats": result.stats}, indent=2))
        else:
            print(f"Nodes: {len(result.nodes)}  Edges: {len(result.edges)}")
            print(f"Alerts: {len(result.alerts)}")
            for alert in result.alerts:
                print(f"- [{alert.severity}] {alert.code}: {alert.message}")
            print("")
            for edge in result.edges[:50]:
                print(
                    f"{edge.chain or '-':<5} | {edge.source} -> {edge.target} | "
                    f"tx={edge.txid or '-'} | dir={edge.direction or '-'} | amount={edge.amount_raw or '-'}"
                )
            if len(result.edges) > 50:
                print(f"... truncated display, total edges = {len(result.edges)}")
    finally:
        await service.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", required=True)
    parser.add_argument("--chain", default=None)
    parser.add_argument("--max-depth", type=int, default=2)
    parser.add_argument("--max-nodes", type=int, default=250)
    parser.add_argument("--max-edges", type=int, default=500)
    parser.add_argument("--tx-limit-per-address", type=int, default=150)
    parser.add_argument("--counterpart-limit-per-tx", type=int, default=40)
    parser.add_argument("--format", choices=["text", "json", "cytoscape"], default="text")
    args = parser.parse_args()
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
