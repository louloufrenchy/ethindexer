from textual.widgets import Static
from datetime import datetime


class SummaryPanel(Static):
    def __init__(self) -> None:
        super().__init__()
        self.update("Forensic Suite v2 Cockpit\n\nLoading...")

    def update_metrics(self, metrics: dict) -> None:
        cps = metrics["checkpoints"]
        counts = metrics["counts"]
        ts: datetime = metrics["ts"]

        def fmt_chain(chain):
            cp = cps.get(chain)
            cnt = counts.get(chain)
            if not cp:
                return f"{chain.upper()}: n/a"
            return (
                f"{chain.upper()}: last_block={cp['last_block']}, "
                f"rows={cnt if cnt is not None else 'n/a'}, "
                f"updated_at={cp['updated_at']}"
            )

        text = "\n".join(
            [
                "Forensic Suite v2 Cockpit",
                f"Last refresh: {ts.isoformat(timespec='seconds')}",
                "",
                fmt_chain("eth"),
                fmt_chain("btc"),
                fmt_chain("tron"),
            ]
        )
        self.update(text)

    def update_error(self, msg: str) -> None:
        self.update(f"Forensic Suite v2 Cockpit\n\nERROR:\n{msg}")
