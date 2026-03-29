from __future__ import annotations

from .models import TraceResult


def to_cytoscape_elements(result: TraceResult) -> list[dict]:
    elements: list[dict] = []

    for node in result.nodes:
        elements.append(
            {
                "data": {
                    "id": node.id,
                    "label": node.label,
                    "kind": node.kind,
                    "chain": node.chain,
                    "depth": node.depth,
                    "tx_count": node.tx_count,
                    **node.attributes,
                }
            }
        )

    for edge in result.edges:
        elements.append(
            {
                "data": {
                    "id": edge.id,
                    "source": edge.source,
                    "target": edge.target,
                    "kind": edge.kind,
                    "chain": edge.chain,
                    "txid": edge.txid,
                    "direction": edge.direction,
                    "contract_address": edge.contract_address,
                    "amount_raw": edge.amount_raw,
                    "block_number": edge.block_number,
                    "weight": edge.weight,
                    **edge.attributes,
                }
            }
        )

    return elements
