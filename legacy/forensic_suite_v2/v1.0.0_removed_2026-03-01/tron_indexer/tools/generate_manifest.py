import yaml
import os

CONFIG_PATH = os.environ.get("CONFIG_PATH", r"C:\development\tron_indexer\config\indexer.yaml")

def main():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    hosts = cfg.get("hosts", [
        {
            "name": "local",
            "chains": cfg.get("chains", ["tron"]),
            "services": ["indexer", "api"],
        }
    ])

    for h in hosts:
        name = h["name"]
        chains = ",".join(h["chains"])
        services = ",".join(h["services"])
        print(f"# Host: {name}")
        print(f"# Chains: {chains}")
        print(f"# Services: {services}")
        print(f"python services/orchestrator.py  # example launcher\n")

if __name__ == "__main__":
    main()
