import strawberry
from typing import List
from ..run_api import pg_pool

@strawberry.type
class Transfer:
    txid: str
    block_number: int
    amount_raw: str
    contract_address: str

@strawberry.type
class Query:
    @strawberry.field
    async def outgoing(self, address: str) -> List[Transfer]:
        async with pg_pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT txid, block_number, amount_raw, contract_address
                FROM address_tx_index
                WHERE address = $1 AND direction = 'out'
            """, address.lower())
            return [Transfer(**dict(r)) for r in rows]

schema = strawberry.Schema(query=Query)
