class TRONPlugin:
    name = "tron"
    description = "TRON tracer plugin"
    def trace(self, target=None):
        return f"[TRON] Trace invoked. Target={target!r}"
