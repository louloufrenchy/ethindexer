from forensic_suite_v2.core.engine import Engine
from forensic_suite_v2.core.plugin_loader import discover_plugins
from forensic_suite_v2.core.logging import get_logger

import importlib
import pkgutil
from pathlib import Path

def discover_plugins():
    plugin_dir = Path("plugins")
    plugins = {}

    for module in pkgutil.iter_modules([str(plugin_dir)]):
        name = module.name
        full_path = f"plugins.{name}.plugin"
        try:
            mod = importlib.import_module(full_path)
            plugins[name] = mod.Plugin()
        except Exception as e:
            print(f"[WARN] Failed to load plugin {name}: {e}")

    return plugins
