from forensic_suite_v2.plugins.eth.plugin import EthPlugin
from forensic_suite_v2.plugins.tron.plugin import TronPlugin
from forensic_suite_v2.plugins.btc.plugin import BtcPlugin

class TRONPlugin:
    name = "tron"
    description = "TRON tracer plugin"

    def trace(self, target=None):
        # Placeholder implementation – extend with real TRON tracing
        return f"[TRON] Trace invoked. Target={target!r}"
