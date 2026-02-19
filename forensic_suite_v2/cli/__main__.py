import sys
import subprocess
from pathlib import Path
from forensic_suite_v2.cli.__main__ import cli

import click

from forensic_suite_v2.core.engine import Engine
from forensic_suite_v2.gui.app import launch_gui as _launch_gui

INSTALL_ROOT = Path(__file__).resolve().parents[2]
PS51 = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"


def _run_ps(script_rel: str):
    script = INSTALL_ROOT / script_rel
    if not script.exists():
        click.echo(f"Script not found: {script}", err=True)
        sys.exit(1)
    subprocess.Popen([PS51, "-ExecutionPolicy", "Bypass", "-File", str(script)])


@click.group()
def cli():
    """Forensic Suite v2 – CLI entrypoint."""
    pass


@cli.command()
def gui():
    """Launch the PySide6 GUI cockpit."""
    _launch_gui()


@cli.command()
@click.option("--chain", type=click.Choice(["btc", "eth", "tron"]), required=True)
def run_indexer(chain: str):
    """Run a single chain indexer via PowerShell script."""
    _run_ps(f"scripts/run_{chain}_indexer.ps1")


@cli.command()
def run_all():
    """Run all indexers via PowerShell script."""
    _run_ps("scripts/run_all_indexers.ps1")


@cli.command()
@click.option(
    "--type",
    "dash",
    type=click.Choice(["btc", "eth", "tron", "multi"]),
    required=True,
)
def dashboard(dash: str):
    """Launch a dashboard PowerShell script."""
    mapping = {
        "btc": "dashboards/btc_dashboard.ps1",
        "eth": "dashboards/eth_dashboard.ps1",
        "tron": "dashboards/tron_dashboard.ps1",
        "multi": "dashboards/multi_chain_dashboard.ps1",
    }
    _run_ps(mapping[dash])


@cli.command()
def health_api():
    """Run the FastAPI health / API server."""
    from forensic_suite_v2.api.app import app
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8080)


if __name__ == "__main__":
    cli()
