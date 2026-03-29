import time
import subprocess
import json
from pathlib import Path
from core.logging import get_logger

log = get_logger("orchestrator")
MANIFEST = Path("chains.json")


def load_manifest():
    with open(MANIFEST) as f:
        return json.load(f)["chains"]


def start_chain(chain: str, cfg: dict):
    services_dir = Path(cfg["indexer_path"]) / "services"
    candidates = list(services_dir.glob("run_*_indexer_v2.py"))
    if not candidates:
        log.warning(f"No launcher found for {chain}")
        return None
    script = candidates[0]
    log.info(f"Starting {chain} via {script}")
    return subprocess.Popen(["python", str(script)])


def orchestrate():
    chains = load_manifest()
    processes = {}

    for name, cfg in chains.items():
        if cfg.get("enabled", False):
            proc = start_chain(name, cfg)
            processes[name] = proc

    try:
        while True:
            time.sleep(5)
            for name, proc in list(processes.items()):
                if proc and proc.poll() is not None:
                    log.warning(f"{name} exited with code {proc.returncode}, restarting...")
                    chains = load_manifest()
                    if chains[name].get("enabled", False):
                        processes[name] = start_chain(name, chains[name])
                    else:
                        log.info(f"{name} disabled in manifest, not restarting.")
                        del processes[name]
    except KeyboardInterrupt:
        log.info("Shutting down orchestrator...")
        for name, proc in processes.items():
            if proc and proc.poll() is None:
                log.info(f"Terminating {name}")
                proc.terminate()


if __name__ == "__main__":
    orchestrate()