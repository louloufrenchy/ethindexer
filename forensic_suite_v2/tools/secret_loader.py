import os, json
from pathlib import Path

SECRET_PATH = Path(os.getenv("FORENSIC_SECRET_PATH", "C:/forensic_secrets/env.json"))

def load_env():
    if not SECRET_PATH.exists():
        raise FileNotFoundError(f"Missing environment file: {SECRET_PATH}")
    return json.loads(SECRET_PATH.read_text())
