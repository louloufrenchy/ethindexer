import json
from pathlib import Path

def load_env(path="env.json"):
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Missing environment file: {path}")
    with open(p, "r") as f:
        return json.load(f)
