class CustomPlugin:
    name = "custom"
    description = "Custom tracer plugin"

    def trace(self, target=None):
        # Placeholder implementation – extend with custom logic
        return f"[CUSTOM] Trace invoked. Target={target!r}"
