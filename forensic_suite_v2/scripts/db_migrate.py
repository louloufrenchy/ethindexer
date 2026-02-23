import argparse
import subprocess
from pathlib import Path
from forensic_suite_v2.core.logging import get_logger
from forensic_suite_v2.scripts.healthcheck import run_healthcheck
from forensic_suite_v2.scripts.operator_console import OperatorConsole

log = get_logger("db_migrate")


def run_psql(command: str, env: dict):
    result = subprocess.run(
        ["psql", "-v", "ON_ERROR_STOP=1", "-c", command],
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        log.error(result.stderr)
        raise RuntimeError(result.stderr)
    log.info(result.stdout)


def migrate_chain(chain: str, sql_dir: Path, env: dict):
    log.info(f"Running migrations for {chain}")
    for sql_file in sorted(sql_dir.glob("*.sql")):
        log.info(f"Applying {sql_file.name}")
        with open(sql_file) as f:
            cmd = f.read()
        run_psql(cmd, env)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--chain", choices=["btc", "eth", "tron", "all"], default="all")
    args = parser.parse_args()

    env = {
        **dict(Path(".env").read_text().splitlines() and {}),
        **dict(),
    }

    base = Path("sql")
    if args.chain in ("btc", "all"):
        migrate_chain("btc", base / "btc", env)
    if args.chain in ("eth", "all"):
        migrate_chain("eth", base / "eth", env)
    if args.chain in ("tron", "all"):
        migrate_chain("tron", base / "tron", env)


if __name__ == "__main__":
    main()
