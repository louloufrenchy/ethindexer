from dataclasses import dataclass
from typing import List

@dataclass
class EthBlock:
    height: int
    txids: List[str]

class EthBlockScanner:
    def __init__(self, config):
        self.config = config

    async def fetch(self, height: int) -> EthBlock:
        txids = [f"eth_tx_{height}_{i}" for i in range(3)]
        return EthBlock(height=height, txids=txids)

    async def get_chain_head(self) -> int:
        # Synthetic chain head for dry-run
        return 1000
