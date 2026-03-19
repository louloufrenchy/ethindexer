from dataclasses import dataclass
from typing import List

@dataclass
class TronBlock:
    height: int
    txids: List[str]

class TronBlockScanner:
    def __init__(self, config):
        self.config = config

    async def fetch(self, height: int) -> TronBlock:
        txids = [f"tron_tx_{height}_{i}" for i in range(4)]
        return TronBlock(height=height, txids=txids)

    async def get_chain_head(self) -> int:
        return 45000000
