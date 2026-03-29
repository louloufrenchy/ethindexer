from pathlib import Path
import importlib
import logging

PLUGIN_ROOT = Path(__file__).resolve().parents[1] / "plugins"

def discover_plugins(enabled_chains=None):
    """
    Discover plugins inside forensic_suite_v2/plugins.
    Only load plugins whose folder name matches enabled chains.
    """
    plugins = {}

    if enabled_chains is None:
        enabled_chains = ["btc", "eth", "tron"]

    for chain in enabled_chains:
        module_path = PLUGIN_ROOT / chain / "plugin.py"
        if not module_path.exists():
            logging.warning(f"Plugin for chain '{chain}' not found at {module_path}")
            continue

        try:
            module_name = f"forensic_suite_v2.plugins.{chain}.plugin"
            module = importlib.import_module(module_name)

            if hasattr(module, "Plugin"):
                plugins[chain] = module.Plugin()
                logging.info(f"Loaded plugin: {chain} ({module_name})")
            else:
                logging.warning(f"Plugin module '{module_name}' missing class Plugin")

        except Exception as exc:
            logging.exception(f"Failed to import plugin module '{chain}': {exc}")

    return plugins
