import json
import subprocess
from pathlib import Path
from forensic_suite_v2.scripts.healthcheck import run_healthcheck
from forensic_suite_v2.scripts.operator_console import OperatorConsole

import sys, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

def load_manifest():
    with open("chains.json", "r") as f:
        return json.load(f)["chains"]

def start_indexer(chain, cfg):
    path = Path(cfg["indexer_path"]) / "services"
    launcher = list(path.glob("run_*_indexer_v2.py"))
    if not launcher:
        print(f"[WARN] No launcher found for {chain}")
        return
    print(f"[INFO] Starting {chain.upper()} indexer...")
    subprocess.Popen(["python", str(launcher[0])])

if __name__ == "__main__":
    chains = load_manifest()
    for chain, cfg in chains.items():
        if cfg["enabled"]:
            start_indexer(chain, cfg)
