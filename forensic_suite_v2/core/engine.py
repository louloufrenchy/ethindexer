class Engine:
    def __init__(self):
        # Holds plugins by name
        self.plugins = {}

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
