from fastapi import APIRouter, Depends
from ..dependencies import get_pg

router = APIRouter(prefix="/tokens", tags=["tokens"])

@router.get("/{contract}")
async def token_info(contract: str, conn=Depends(get_pg)):
    row = await conn.fetchrow("""
        SELECT contract_address, symbol, name, decimals
        FROM token_registry
        WHERE contract_address = $1
    """, contract.lower())
    return dict(row) if row else {}
