# forensic_suite_v2/scripts/healthcheck_core.py

import json
import subprocess
from pathlib import Path

def load_manifest():
    with open("chains.json") as f:
        return json.load(f)["chains"]

def check_process(name):
    try:
        out = subprocess.check_output(f"tasklist | findstr {name}", shell=True)
        return True if out else False
    except:
        return False

def check_chain(chain, cfg):
    print(f"\n=== {chain.upper()} HEALTH ===")
    indexer_path = Path(cfg["indexer_path"])
    service_name = indexer_path.name

    running = check_process(service_name)
    print(f"Indexer running: {running}")

    config_exists = Path(cfg["config"]).exists()
    print(f"Config present: {config_exists}")

def run_healthcheck():
    chains = load_manifest()
    for chain, cfg in chains.items():
        if cfg["enabled"]:
            check_chain(chain, cfg)
