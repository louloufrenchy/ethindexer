import os, json
from pathlib import Path

<<<<<<< HEAD
SECRET_PATH = Path(os.getenv("FORENSIC_SECRET_PATH", "C:/forensic_secrets/env.json"))
=======
SECRET_PATH = Path(os.getenv("FORENSIC_SECRET_PATH", "F:/forensic_secrets/env.json"))
>>>>>>> master

def load_env():
    if not SECRET_PATH.exists():
        raise FileNotFoundError(f"Missing environment file: {SECRET_PATH}")
    return json.loads(SECRET_PATH.read_text())
