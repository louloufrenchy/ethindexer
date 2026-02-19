from forensic_suite_v2.core.engine import Engine
from forensic_suite_v2.core.plugin_loader import discover_plugins
from forensic_suite_v2.core.logging import get_logger

import logging
from pathlib import Path

def get_logger(name: str):
    log_dir = Path("logs")
    log_dir.mkdir(exist_ok=True)

    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)

    file_handler = logging.FileHandler(log_dir / f"{name}.log")
    formatter = logging.Formatter(
        "%(asctime)s | %(levelname)s | %(name)s | %(message)s"
    )
    file_handler.setFormatter(formatter)

    if not logger.handlers:
        logger.addHandler(file_handler)

    return logger
