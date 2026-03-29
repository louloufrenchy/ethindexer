import logging

class Engine:
    """
    Core engine responsible for:
    - holding plugin instances
    - dispatching trace requests
    """

    def __init__(self):
        self.plugins = {}

    def trace(self, chain: str, target=None):
        """
        Dispatch a trace request to the appropriate plugin.
        """
        if chain not in self.plugins:
            raise ValueError(f"No plugin registered for chain '{chain}'")

        plugin = self.plugins[chain]

        try:
            logging.info(f"Engine.trace: chain={chain}, target={target}")
            return plugin.trace(target)
        except Exception as exc:
            logging.exception(f"Trace failed for chain '{chain}': {exc}")
            raise
