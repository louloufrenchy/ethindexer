import logging
import time
from pathlib import Path

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


def get_logger(name: str = "forensic_suite") -> JsonLogger:
    log_dir = Path("logs")
    log_dir.mkdir(exist_ok=True)

    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)

    if not logger.handlers:
        file_handler = logging.FileHandler(log_dir / f"{name}.log")
        formatter = logging.Formatter("%(message)s")
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

    return JsonLogger(logger, {})