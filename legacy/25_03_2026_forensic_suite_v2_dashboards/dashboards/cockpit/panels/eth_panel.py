from textual.widgets import Static


class EthPanel(Static):
    def __init__(self) -> None:
        super().__init__()
        self.update("ETH\n\nLoading...")

    def update_chain(self, metrics: dict, chain: str) -> None:
        cp = metrics["checkpoints"].get(chain)
        cnt = metrics["counts"].get(chain)
        if not cp:
            self.update("ETH\n\nNo checkpoint data.")
            return

        text = (
            "ETH\n\n"
            f"last_block: {cp['last_block']}\n"
            f"rows: {cnt if cnt is not None else 'n/a'}\n"
            f"updated_at: {cp['updated_at']}\n"
        )
        self.update(text)
