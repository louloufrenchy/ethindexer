from forensic_suite_v2.plugins.eth.plugin import EthPlugin
from forensic_suite_v2.plugins.tron.plugin import TronPlugin
from forensic_suite_v2.plugins.btc.plugin import BtcPlugin

class CustomPlugin:
    name = "custom"
    description = "Custom tracer plugin"

    def trace(self, target=None):
        # Placeholder implementation – extend with custom logic
        return f"[CUSTOM] Trace invoked. Target={target!r}"
