class ETHPlugin:
    name = "eth"
    description = "Ethereum tracer plugin"
    def trace(self, target=None):
        return f"[ETH] Trace invoked. Target={target!r}"
