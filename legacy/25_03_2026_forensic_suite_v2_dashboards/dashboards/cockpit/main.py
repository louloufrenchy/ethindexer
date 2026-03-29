import asyncio
import asyncpg
from datetime import datetime

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Static

from .panels.summary_panel import SummaryPanel
from .panels.eth_panel import EthPanel
from .panels.btc_panel import BtcPanel
from .panels.tron_panel import TronPanel


DB_DSN = "postgresql://postgres:Str0ngPassw0rd2025@192.168.0.28:5432/forensic"
REFRESH_SECONDS = 5


async def fetch_metrics(conn):
    # index_checkpoint
    rows = await conn.fetch(
        "SELECT chain, last_block, updated_at FROM index_checkpoint ORDER BY chain"
    )
    checkpoints = {r["chain"]: dict(r) for r in rows}

    # counts
    counts = {}
    for chain, table in [
        ("eth", "eth_transactions"),
        ("btc", "btc_transactions"),
        ("tron", "tron_transactions"),
    ]:
        try:
            c = await conn.fetchval(f"SELECT COUNT(*) FROM {table}")
        except Exception:
            c = None
        counts[chain] = c

    return {
        "checkpoints": checkpoints,
        "counts": counts,
        "ts": datetime.now(),
    }


class ForensicCockpit(App):
    CSS_PATH = None
    BINDINGS = [("q", "quit", "Quit")]

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._conn = None
        self.summary_panel: SummaryPanel | None = None
        self.eth_panel: EthPanel | None = None
        self.btc_panel: BtcPanel | None = None
        self.tron_panel: TronPanel | None = None

    async def on_mount(self) -> None:
        self._conn = await asyncpg.connect(dsn=DB_DSN)
        self.set_interval(REFRESH_SECONDS, self.refresh_metrics)

    def compose(self) -> ComposeResult:
        self.summary_panel = SummaryPanel()
        self.eth_panel = EthPanel()
        self.btc_panel = BtcPanel()
        self.tron_panel = TronPanel()

        yield Vertical(
            self.summary_panel,
            Horizontal(
                self.eth_panel,
                self.btc_panel,
                self.tron_panel,
            ),
        )

    async def refresh_metrics(self) -> None:
        try:
            metrics = await fetch_metrics(self._conn)
        except Exception as e:
            self.summary_panel.update_error(str(e))
            return

        self.summary_panel.update_metrics(metrics)
        self.eth_panel.update_chain(metrics, "eth")
        self.btc_panel.update_chain(metrics, "btc")
        self.tron_panel.update_chain(metrics, "tron")

    async def on_unmount(self) -> None:
        if self._conn:
            await self._conn.close()


if __name__ == "__main__":
    asyncio.run(ForensicCockpit().run_async())
