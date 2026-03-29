class BTCPlugin:
    name = "btc"
    description = "Bitcoin tracer plugin"
    def trace(self, target=None):
        return f"[BTC] Trace invoked. Target={target!r}"
