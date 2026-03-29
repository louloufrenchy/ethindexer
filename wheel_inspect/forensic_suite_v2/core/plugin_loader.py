import importlib
import pkgutil
from pathlib import Path
import forensic_suite_v2

def discover_plugins():
    """
    Dynamically discover and load all plugins inside forensic_suite_v2/plugins.
    Returns a dict: { plugin_name: plugin_instance }
    """
    plugin_dir = Path(forensic_suite_v2.__file__).parent / "plugins"
    plugins = {}

    for module in pkgutil.iter_modules([str(plugin_dir)]):
        name = module.name
        full_path = f"forensic_suite_v2.plugins.{name}.plugin"
        try:
            mod = importlib.import_module(full_path)
            plugins[name] = mod.Plugin()
        except Exception as e:
            print(f"[WARN] Failed to load plugin {name}: {e}")

    return plugins

load_plugins = discover_plugins

load_plugins = discover_plugins
