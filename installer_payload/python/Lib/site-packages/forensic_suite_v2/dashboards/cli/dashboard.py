import asyncio
import os
import sys
from colorama import init, Fore, Style

from forensic_suite_v2.dashboards.data import DashboardDataService
from forensic_suite_v2.dashboards.data.manager import ServiceManager

init(autoreset=True)
manager = ServiceManager()


def center_text(text, width=110):
    return text.center(width)


def color_status(status: str) -> str:
    s = (status or "").upper()
    if s == "RUNNING":
        return f"{Fore.GREEN}{s}{Style.RESET_ALL}"
    if s == "STOPPED":
        return f"{Fore.RED}{s}{Style.RESET_ALL}"
    if s == "ERROR":
        return f"{Fore.RED}{Style.BRIGHT}{s}{Style.RESET_ALL}"
    return f"{Fore.YELLOW}{s}{Style.RESET_ALL}"


def color_health(health: str) -> str:
    h = (health or "").upper()
    if h == "HEALTHY":
        return f"{Fore.GREEN}{h}{Style.RESET_ALL}"
    if h in {"DOWN", "ERROR"}:
        return f"{Fore.RED}{Style.BRIGHT}{h}{Style.RESET_ALL}"
    if h in {"NO_PROCESS", "UNKNOWN"}:
        return f"{Fore.YELLOW}{h}{Style.RESET_ALL}"
    return h


async def run(refresh_interval=30):
    service = DashboardDataService()
    await service.connect()
    width = 110

    try:
        while True:
            os.system("cls" if os.name == "nt" else "clear")
            summary = await service.get_cluster_summary()

            print(
                "\n"
                + center_text(
                    f"{Fore.CYAN}{Style.BRIGHT}=== FORENSIC CLUSTER CONSOLE ==={Style.RESET_ALL}",
                    width,
                )
            )
            print(center_text(f"Refreshed: {summary.generated_at}", width) + "\n")

            # --- Distributed Node Status Section ---
            print(
                center_text(
                    f"{Fore.YELLOW}--- REMOTE SERVICE NODES (SSH) ---{Style.RESET_ALL}",
                    width,
                )
            )

            nodes = await manager.get_cluster_status()

            if not nodes:
                print(
                    center_text(
                        f"{Fore.RED}⚠️ ALL REMOTE NODES UNREACHABLE{Style.RESET_ALL}",
                        width,
                    )
                )
            else:
                header = f"{'NODE':<15} | {'CHAIN':<6} | {'SERVICE':<22} | {'STATUS':<10} | {'HEALTH':<10}"
                print(center_text(header, width))
                print(center_text("-" * len(header), width))

                for n in nodes:
                    row = (
                        f"{n['node']:<15} | "
                        f"{n['chain']:<6} | "
                        f"{n['service']:<22} | "
                        f"{color_status(n['status']):<19} | "
                        f"{color_health(n.get('health', 'UNKNOWN')):<19}"
                    )
                    print(center_text(row, width))

            # --- Optional remote errors section ---
            if manager.last_errors:
                print("\n" + center_text(f"{Fore.RED}--- LAST REMOTE ERRORS ---{Style.RESET_ALL}", width))
                for ip, err in manager.last_errors.items():
                    trimmed = (err or "").strip().replace("\n", " ")[:140]
                    print(center_text(f"{ip}: {trimmed}", width))

            # --- Chain Data Section ---
            print("\n" + center_text("-" * 80, width))
            head = f"{'CHAIN':<8} | {'STATUS':<10} | {'LAST BLOCK':<12} | {'BPM':<8} | {'AGE':<8}"
            print(center_text(head, width))
            print(center_text("-" * 80, width))

            for s in summary.snapshots:
                row = (
                    f"{s.chain.upper():<8} | "
                    f"{s.status:<10} | "
                    f"{s.last_block:<12,} | "
                    f"{s.blocks_per_min:<8.2f} | "
                    f"{s.age_seconds:<8}"
                )
                print(center_text(row, width))

            print("\n" + center_text(f"{Style.DIM}Press CTRL+C to Exit{Style.RESET_ALL}", width))
            await asyncio.sleep(refresh_interval)

    finally:
        close_method = getattr(service, "close", None)
        if callable(close_method):
            maybe_coro = close_method()
            if asyncio.iscoroutine(maybe_coro):
                await maybe_coro


if __name__ == "__main__":
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        sys.exit(0)
