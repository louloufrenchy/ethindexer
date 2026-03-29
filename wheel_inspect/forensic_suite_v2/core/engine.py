from forensic_suite_v2.core.plugin_loader import discover_plugins
from forensic_suite_v2.core.fs_logging import get_logger
from forensic_suite_v2.core.indexer_engine import BaseIndexerService

class Engine:
    def __init__(self):
        # Holds plugins by name
        self.plugins = discover_plugins()

    def register_plugin(self, plugin):
        """
        Register a plugin instance.
        Plugin must define:
            - name (str)
            - description (str)
            - trace(target) method
        """
        name = plugin.name.lower()
        self.plugins[name] = plugin

    def trace(self, chain, target=None):
        """
        Run the tracer for a specific chain.
        """
        chain = chain.lower()
        if chain not in self.plugins:
            raise ValueError(f"No plugin registered for chain '{chain}'")

        plugin = self.plugins[chain]
        return plugin.trace(target)
