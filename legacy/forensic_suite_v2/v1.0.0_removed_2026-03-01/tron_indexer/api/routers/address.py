from fastapi import APIRouter, Depends
from ..dependencies import get_pg

router = APIRouter(prefix="/address", tags=["address"])

@router.get("/{address}/outgoing")
async def outgoing(address: str, conn=Depends(get_pg)):
    rows = await conn.fetch("""
        SELECT txid, block_number, amount_raw, contract_address
        FROM address_tx_index
        WHERE address = $1 AND direction = 'out'
        ORDER BY block_number
    """, address.lower())
    return [dict(r) for r in rows]
