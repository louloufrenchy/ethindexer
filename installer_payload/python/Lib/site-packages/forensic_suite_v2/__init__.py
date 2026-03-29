"""
Forensic Suite v2 — Unified Multi‑Chain Forensic Platform
"""

from .core.engine import Engine
from .core.plugin_loader import discover_plugins
from .core.fs_logging import get_logger

from .btc_indexer.services.run_btc_indexer_v2 import main as run_btc
from .eth_indexer.services.run_eth_indexer_v2 import main as run_eth
from .tron_indexer.services.run_tron_indexer_v2 import main as run_tron

from .scripts.healthcheck import run_healthcheck
from .scripts.operator_console import OperatorConsole

__version__ = "0.1.3"

__all__ = [
    "Engine",
    "discover_plugins",
    "get_logger",
    "run_btc",
    "run_eth",
    "run_tron",
    "run_healthcheck",
    "OperatorConsole",
]
