from pathlib import Path

def validate_environment():
    """
    Minimal environment validator.
    Ensures required environment files exist.
    """

    required_files = [
        "chains.json",
    ]

    missing = [f for f in required_files if not Path(f).exists()]

    if missing:
        raise FileNotFoundError(f"Missing required environment files: {missing}")

    return True
