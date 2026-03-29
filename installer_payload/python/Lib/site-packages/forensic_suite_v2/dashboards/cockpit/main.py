from __future__ import annotations

from textual.app import App, ComposeResult
from textual.containers import Vertical
from textual.widgets import DataTable, Footer, Header, Static

from forensic_suite_v2.dashboards.data import DashboardDataService
from forensic_suite_v2.dashboards.data.manager import ServiceManager


class CockpitApp(App):
    TITLE = "Forensic Multi-Node Cockpit"
    BINDINGS = [
        ("r", "refresh", "Restart"),
        ("q", "quit", "Quit"),
    ]

    def __init__(self):
        super().__init__()
        self.manager = ServiceManager()
        self.data_service = DashboardDataService()

    def compose(self) -> ComposeResult:
        yield Header()

        with Vertical():
            yield Static("🖥 NODE STATUS (SSH)")
            node_table = DataTable(id="node_table")
            node_table.add_columns("Node IP", "Chain", "Service", "Status", "Health")
            yield node_table

            yield Static("⚡ DATA FEEDS")
            feed_table = DataTable(id="feed_table")
            feed_table.add_columns("Chain", "Status", "Last Block", "BPM", "Age(s)")
            yield feed_table

            yield Static("⚠ REMOTE DIAGNOSTICS")
            yield Static("", id="errors_box")

        yield Footer()

    async def on_mount(self) -> None:
        await self.data_service.connect()
        await self.refresh_tables()
        self.set_interval(15, self.refresh_tables)

    async def on_unmount(self) -> None:
        close_method = getattr(self.data_service, "close", None)
        if callable(close_method):
            maybe_coro = close_method()
            import asyncio
            if asyncio.iscoroutine(maybe_coro):
                await maybe_coro

    async def action_refresh(self) -> None:
        await self.refresh_tables()

    async def refresh_tables(self) -> None:
        node_table = self.query_one("#node_table", DataTable)
        feed_table = self.query_one("#feed_table", DataTable)
        errors_box = self.query_one("#errors_box", Static)

        node_table.clear(columns=False)
        feed_table.clear(columns=False)

        # Node / service status
        nodes = await self.manager.get_cluster_status()
        if nodes:
            for n in nodes:
                node_table.add_row(
                    str(n.get("node", "")),
                    str(n.get("chain", "")),
                    str(n.get("service", "")),
                    str(n.get("status", "")),
                    str(n.get("health", "")),
                )
        else:
            node_table.add_row("N/A", "N/A", "N/A", "ERROR", "DOWN")

        # Chain feed summary
        summary = await self.data_service.get_cluster_summary()
        for s in summary.snapshots:
            feed_table.add_row(
                str(s.chain).upper(),
                str(s.status),
                f"{s.last_block}",
                f"{s.blocks_per_min:.2f}",
                f"{s.age_seconds}",
            )

        # Diagnostics
        if self.manager.last_errors:
            text = "\n".join(f"[{k}] {v}" for k, v in self.manager.last_errors.items())
        else:
            text = "No remote errors."
        errors_box.update(text)


def main():
    app = CockpitApp()
    app.run()


if __name__ == "__main__":
    main()
