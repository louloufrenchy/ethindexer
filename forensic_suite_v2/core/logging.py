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
import logging
import time
import orjson

class JsonLogger(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        base = {
            "msg": msg,
            "ts": time.time(),
            "component": "core",
        }
        if "extra" in kwargs:
            base.update(kwargs["extra"])
            del kwargs["extra"]
        return orjson.dumps(base).decode(), kwargs

def get_logger(name: str = "forensic_suite"):
    return JsonLogger(logging.getLogger(name), {})
