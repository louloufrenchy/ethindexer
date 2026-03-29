import subprocess
import time
from pathlib import Path
from typing import List, Dict, Any

import yaml

POWERSHELL_EXE = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"


def run(cmd: List[str]) -> int:
    print(f"[CMD] {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout.strip())
    if result.stderr:
        print(result.stderr.strip())
    return result.returncode


def parse_env_file(env_path: Path) -> List[str]:
    if not env_path.exists():
        raise RuntimeError(f".env not found at {env_path}")

    entries: List[str] = []
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key:
            entries.append(f"{key}={value}")
    return entries


def load_enabled_chains(config_path: Path) -> Dict[str, bool]:
    raw = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    return {
        "btc": bool(raw.get("btc", {}).get("enabled", False)),
        "eth": bool(raw.get("eth", {}).get("enabled", False)),
        "tron": bool(raw.get("tron", {}).get("enabled", False)),
    }


def remove_service_if_present(service_name: str) -> None:
    print(f"[INFO] Removing existing service if present: {service_name}")
    subprocess.run(["sc", "stop", service_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sc", "delete", service_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)


def install_python_service(
    nssm_path: Path,
    service_name: str,
    python_exe: Path,
    script_path: Path,
    app_directory: Path,
    logs_root: Path,
    env_entries: List[str],
) -> None:
    if run([str(nssm_path), "install", service_name, str(python_exe)]) != 0:
        raise RuntimeError(f"Failed to install {service_name}")

    if run([str(nssm_path), "set", service_name, "AppParameters", str(script_path)]) != 0:
        raise RuntimeError(f"Failed to set AppParameters for {service_name}")

    if run([str(nssm_path), "set", service_name, "AppDirectory", str(app_directory)]) != 0:
        raise RuntimeError(f"Failed to set AppDirectory for {service_name}")

    if run([str(nssm_path), "set", service_name, "Start", "SERVICE_AUTO_START"]) != 0:
        raise RuntimeError(f"Failed to set Start for {service_name}")

    if run([str(nssm_path), "set", service_name, "AppExit", "Default", "Restart"]) != 0:
        raise RuntimeError(f"Failed to set AppExit for {service_name}")

    run([str(nssm_path), "set", service_name, "AppEnvironment", ""])

    app_environment_extra = [
        f"PYTHONPATH={app_directory}",
        "PYTHONUNBUFFERED=1",
        "PYTHONIOENCODING=utf-8",
    ] + env_entries

    if run([str(nssm_path), "set", service_name, "AppEnvironmentExtra", *app_environment_extra]) != 0:
        raise RuntimeError(f"Failed to set AppEnvironmentExtra for {service_name}")

    if run([str(nssm_path), "set", service_name, "AppStdout", str(logs_root / f"{service_name}.out.log")]) != 0:
        raise RuntimeError(f"Failed to set AppStdout for {service_name}")

    if run([str(nssm_path), "set", service_name, "AppStderr", str(logs_root / f"{service_name}.err.log")]) != 0:
        raise RuntimeError(f"Failed to set AppStderr for {service_name}")

    run(["sc", "failure", service_name, "reset=", "0", "actions=", "restart/5000"])


def install_powershell_service(
    nssm_path: Path,
    service_name: str,
    script_path: Path,
    app_directory: Path,
    logs_root: Path,
    env_entries: List[str],
    pythonpath_root: Path,
) -> None:
    if run([str(nssm_path), "install", service_name, POWERSHELL_EXE]) != 0:
        raise RuntimeError(f"Failed to install {service_name}")

    app_parameters = f'-NoProfile -ExecutionPolicy Bypass -File "{script_path}"'
    if run([str(nssm_path), "set", service_name, "AppParameters", app_parameters]) != 0:
        raise RuntimeError(f"Failed to set AppParameters for {service_name}")

    if run([str(nssm_path), "set", service_name, "AppDirectory", str(app_directory)]) != 0:
        raise RuntimeError(f"Failed to set AppDirectory for {service_name}")

    if run([str(nssm_path), "set", service_name, "Start", "SERVICE_AUTO_START"]) != 0:
        raise RuntimeError(f"Failed to set Start for {service_name}")

    if run([str(nssm_path), "set", service_name, "AppExit", "Default", "Restart"]) != 0:
        raise RuntimeError(f"Failed to set AppExit for {service_name}")

    run([str(nssm_path), "set", service_name, "AppEnvironment", ""])

    app_environment_extra = [
        f"PYTHONPATH={pythonpath_root}",
        "PYTHONUNBUFFERED=1",
        "PYTHONIOENCODING=utf-8",
    ] + env_entries

    if run([str(nssm_path), "set", service_name, "AppEnvironmentExtra", *app_environment_extra]) != 0:
        raise RuntimeError(f"Failed to set AppEnvironmentExtra for {service_name}")

    if run([str(nssm_path), "set", service_name, "AppStdout", str(logs_root / f"{service_name}.out.log")]) != 0:
        raise RuntimeError(f"Failed to set AppStdout for {service_name}")

    if run([str(nssm_path), "set", service_name, "AppStderr", str(logs_root / f"{service_name}.err.log")]) != 0:
        raise RuntimeError(f"Failed to set AppStderr for {service_name}")

    run(["sc", "failure", service_name, "reset=", "0", "actions=", "restart/5000"])


def start_service(service_name: str) -> None:
    print(f"[INFO] Starting service: {service_name}")
    run(["sc", "start", service_name])


def main() -> None:
    print("=== Install Forensic Suite Services (Hardened Production Installer) ===")

    script_root = Path(__file__).resolve().parent
    package_root = script_root.parent
    resolved_root = package_root.parent

    nssm_path = resolved_root / "tools" / "nssm" / "nssm.exe"
    python_exe = resolved_root / "python" / "python.exe"
    config_path = resolved_root / "forensic_suite_v2" / "config" / "indexer.yaml"

    logs_root = Path(r"C:\forensic_suite_logs")
    state_root = Path(r"C:\forensic_state")
    secrets_root = Path(r"C:\forensic_secrets")
    env_file = secrets_root / ".env"

    logs_root.mkdir(parents=True, exist_ok=True)
    state_root.mkdir(parents=True, exist_ok=True)
    (state_root / "btc").mkdir(parents=True, exist_ok=True)
    (state_root / "eth").mkdir(parents=True, exist_ok=True)
    (state_root / "tron").mkdir(parents=True, exist_ok=True)

    if not nssm_path.exists():
        raise RuntimeError(f"NSSM not found at {nssm_path}")
    if not python_exe.exists():
        raise RuntimeError(f"Python runtime not found at {python_exe}")
    if not config_path.exists():
        raise RuntimeError(f"Config file not found at {config_path}")

    env_entries = parse_env_file(env_file)
    enabled = load_enabled_chains(config_path)

    print(f"[INFO] ResolvedRoot : {resolved_root}")
    print(f"[INFO] NSSM         : {nssm_path}")
    print(f"[INFO] Python       : {python_exe}")
    print(f"[INFO] Secrets file : {env_file}")
    print(f"[INFO] Env entries  : {len(env_entries)}")
    print(f"[INFO] Enabled      : btc={enabled['btc']} eth={enabled['eth']} tron={enabled['tron']}")

    chain_services: List[Dict[str, Any]] = [
        {
            "name": "btc_indexer",
            "chain": "btc",
            "type": "python",
            "script": resolved_root / "forensic_suite_v2" / "btc_indexer" / "services" / "run_btc_indexer_v2.py",
            "app_directory": resolved_root,
        },
        {
            "name": "eth_indexer",
            "chain": "eth",
            "type": "python",
            "script": resolved_root / "forensic_suite_v2" / "eth_indexer" / "services" / "run_eth_indexer_v2.py",
            "app_directory": resolved_root,
        },
        {
            "name": "tron_indexer",
            "chain": "tron",
            "type": "python",
            "script": resolved_root / "forensic_suite_v2" / "tron_indexer" / "services" / "run_tron_indexer_v2.py",
            "app_directory": resolved_root,
        },
    ]

    orchestrator = {
        "name": "forensic_orchestrator",
        "type": "powershell",
        "script": resolved_root / "forensic_suite_v2" / "scripts" / "windows_orchestrator_service.ps1",
        "app_directory": resolved_root / "forensic_suite_v2",
    }

    for svc in chain_services + [orchestrator]:
        if not svc["script"].exists():
            raise RuntimeError(f"Required script not found for {svc['name']}: {svc['script']}")

    for svc in chain_services:
        remove_service_if_present(svc["name"])

    for svc in chain_services:
        if not enabled[svc["chain"]]:
            print(f"[INFO] Skipping disabled chain service: {svc['name']}")
            continue

        install_python_service(
            nssm_path=nssm_path,
            service_name=svc["name"],
            python_exe=python_exe,
            script_path=svc["script"],
            app_directory=svc["app_directory"],
            logs_root=logs_root,
            env_entries=env_entries,
        )
        start_service(svc["name"])
        time.sleep(2)

    remove_service_if_present(orchestrator["name"])
    install_powershell_service(
        nssm_path=nssm_path,
        service_name=orchestrator["name"],
        script_path=orchestrator["script"],
        app_directory=orchestrator["app_directory"],
        logs_root=logs_root,
        env_entries=env_entries,
        pythonpath_root=resolved_root,
    )
    start_service(orchestrator["name"])

    print("[OK] Hardened service installation complete.")


if __name__ == "__main__":
    main()
