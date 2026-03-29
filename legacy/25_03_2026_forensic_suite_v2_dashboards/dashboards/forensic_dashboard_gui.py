import asyncio
import logging
from pathlib import Path
from tkinter import Tk, ttk, messagebox

from forensic_suite_v2.dashboards.dashboard_common import load_config, get_db_pool, fetch_row

INSTALL_ROOT = Path(__file__).resolve().parents[1]

REFRESH_MS = 3000  # 3 seconds

class MultiChainDashboard:
    def __init__(self):
        self.cfg = load_config()
        self.enabled = self._enabled_chains()

        self.root = Tk()
        self.root.title("Forensic Suite Production Dashboard")
        self.root.geometry("1100x500")

        self.tree = self._build_table()
        self.pool = None

        self.root.after(0, self._start_async)
        self.root.mainloop()

    def _enabled_chains(self):
        chains = []
        for c in ["btc", "eth", "tron"]:
            if self.cfg.get(c, {}).get("enabled", False):
                chains.append(c)
        return chains or ["btc", "eth", "tron"]

    def _build_table(self):
        cols = [
            "Chain", "Status", "Last Block", "Chain Head",
            "Lag", "Updated (UTC)", "Blocks Table",
            "Transactions Table", "Extra Table Count"
        ]

        tree = ttk.Treeview(self.root, columns=cols, show="headings")
        for c in cols:
            tree.heading(c, text=c)
            tree.column(c, width=120)

        tree.pack(fill="both", expand=True)
        return tree

    async def _start_async(self):
        try:
            self.pool = await get_db_pool(self.cfg)
        except Exception as exc:
            messagebox.showerror("Database error", str(exc))
            return

        self._schedule_refresh()

    def _schedule_refresh(self):
        self.root.after(REFRESH_MS, lambda: asyncio.create_task(self._refresh()))

    async def _refresh(self):
        self.tree.delete(*self.tree.get_children())

        for chain in self.enabled:
            try:
                row = await self._fetch_chain_status(chain)
                self.tree.insert("", "end", values=row)
            except Exception as exc:
                err = str(exc)
                self.tree.insert("", "end", values=[chain, "ERROR", err, "", "", "", "", "", ""])

        self._schedule_refresh()

    async def _fetch_chain_status(self, chain: str):
        """
        Query unified schema tables:
        - {chain}_blocks
        - {chain}_transactions
        - {chain}_extra
        """
        last_block = await fetch_row(self.pool, f"SELECT MAX(height) AS h FROM {chain}_blocks")
        head = await fetch_row(self.pool, f"SELECT chain_head FROM chain_status WHERE chain=$1", chain)
        extra = await fetch_row(self.pool, f"SELECT COUNT(*) AS c FROM {chain}_extra")

        last_height = last_block["h"] if last_block else None
        chain_head = head["chain_head"] if head else None
        lag = (chain_head - last_height) if (chain_head and last_height) else None

        return [
            chain.upper(),
            "OK" if lag is not None and lag < 5 else "LAG",
            last_height,
            chain_head,
            lag,
            head.get("updated_utc") if head else "",
            f"{chain}_blocks",
            f"{chain}_transactions",
            extra["c"] if extra else 0,
        ]


def main():
    MultiChainDashboard()


if __name__ == "__main__":
    main()
