from textual.widgets import Static


class TronPanel(Static):
    def __init__(self) -> None:
        super().__init__()
        self.update("TRON\n\nLoading...")

    def update_chain(self, metrics: dict, chain: str) -> None:
        cp = metrics["checkpoints"].get(chain)
        cnt = metrics["counts"].get(chain)
        if not cp:
            self.update("TRON\n\nNo checkpoint data.")
            return

        text = (
            "TRON\n\n"
            f"last_block: {cp['last_block']}\n"
            f"rows: {cnt if cnt is not None else 'n/a'}\n"
            f"updated_at: {cp['updated_at']}\n"
        )
        self.update(text)
