import json
import os
import typing
from forensic_suite_v2.tools.env_loader import load_env
from forensic_suite_v2.tools.validators import validate_environment
from pathlib import Path
from typing import Dict, Tuple

from forensic_suite_v2.tools.env_loader import load_env
from forensic_suite_v2.tools.validators import validate_environment

env = load_env("env.json")
for key, value in env.items():
    os.environ[key] = value


def validate_env_and_endpoints() -> Dict[str, Tuple[bool, str]]:
    """
    Validates presence and basic format of required .env keys.
    Returns a dict of key → (is_valid, error_message_if_any)
    """

    required_keys = {
        "QUICKNODE_ETH_HTTP": "ETH QuickNode HTTP endpoint",
        "QUICKNODE_ETH_WSS": "ETH QuickNode WebSocket endpoint",
        "QUICKNODE_TRON_ENDPOINT_1": "TRON QuickNode endpoint #1",
        "QUICKNODE_TRON_ENDPOINT_2": "TRON QuickNode endpoint #2",
    }

    results: Dict[str, Tuple[bool, str]] = {}

    for key, desc in required_keys.items():
        value = os.getenv(key)

        if not value:
            results[key] = (False, f"{desc} not set")
            continue

        if not value.startswith(("http://", "https://", "ws://", "wss://")):
            results[key] = (False, f"{desc} is malformed: {value}")
            continue

        results[key] = (True, "")

    return results


if __name__ == "__main__":
    from pprint import pprint
    pprint(validate_env_and_endpoints())
