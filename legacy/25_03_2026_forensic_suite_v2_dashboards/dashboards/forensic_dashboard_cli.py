import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import argparse
import asyncio
import os
from typing import List

from dashboard_common import connect, format_dt, format_int, get_all_snapshots, utc_now_str


def clear() -> None:
    os.system("cls" if os.name == "nt" else "clear")


def progress_bar(current: int | None, total: int | None, width: int = 28) -> str:
    if current is None or total is None or total <= 0:
        return "[" + ("-" * width) + "]"
    pct = max(min(current / total, 1.0), 0.0)
    filled = int(width * pct)
    return "[" + ("#" * filled) + ("-" * (width - filled)) + "]"


def render_table(snapshots) -> str:
    lines: List[str] = []
    lines.append("=== Forensic Suite Production Dashboard (CLI) ===")
    lines.append(f"Time:   {utc_now_str()}")
    lines.append("")
    lines.append("CHAIN | STATUS      | LAST BLOCK | CHAIN HEAD | LAG      | UPDATED (UTC)")
    lines.append("------|-------------|------------|------------|----------|----------------------")

    for s in snapshots:
        lines.append(
            f"{s.chain.upper():<5} | "
            f"{s.status:<11} | "
            f"{format_int(s.last_block):>10} | "
            f"{format_int(s.chain_head):>10} | "
            f"{format_int(s.lag):>8} | "
            f"{format_dt(s.updated_at)}"
        )

    lines.append("")
    for s in snapshots:
        lines.append(f"--- {s.chain.upper()} DETAIL ---")
        lines.append(f"Progress: {progress_bar(s.last_block, s.chain_head)}")
        lines.append(f"Blocks table:       {format_int(s.blocks_count)}")
        lines.append(f"Transactions table: {format_int(s.tx_count)}")
        lines.append(f"{s.extra_label}: {format_int(s.extra_count)}")
        lines.append("")

    lines.append("Press CTRL+C to exit.")
    return "\n".join(lines)


async def run_dashboard(refresh_seconds: float, config_path: str | None) -> None:
    conn = await connect(config_path)
    try:
        while True:
            snapshots = await get_all_snapshots(conn)
            clear()
            print(render_table(snapshots))
            await asyncio.sleep(refresh_seconds)
    finally:
        await conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Forensic Suite CLI dashboard")
    parser.add_argument("--refresh", type=float, default=2.0, help="Refresh interval in seconds")
    parser.add_argument("--config", type=str, default=None, help="Optional config file path")
    args = parser.parse_args()

    try:
        asyncio.run(run_dashboard(args.refresh, args.config))
    except KeyboardInterrupt:
        print("\n[CLI DASHBOARD] Exiting...")


if __name__ == "__main__":
    main()
