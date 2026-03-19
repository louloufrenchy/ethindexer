from dataclasses import dataclass
from typing import List

@dataclass
class BtcBlock:
    height: int
    txids: List[str]

class BtcBlockScanner:
    def __init__(self, config):
        self.config = config

    async def fetch(self, height: int) -> BtcBlock:
        txids = [f"btc_tx_{height}_{i}" for i in range(2)]
        return BtcBlock(height=height, txids=txids)

    async def get_chain_head(self) -> int:
        return 500000
