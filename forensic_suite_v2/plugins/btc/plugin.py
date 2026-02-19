from forensic_suite_v2.plugins.eth.plugin import EthPlugin
from forensic_suite_v2.plugins.tron.plugin import TronPlugin
from forensic_suite_v2.plugins.btc.plugin import BtcPlugin

class BTCPlugin:
    name = "btc"
    description = "Bitcoin tracer plugin"

    def trace(self, target=None):
        # Placeholder implementation – extend with real BTC tracing
        return f"[BTC] Trace invoked. Target={target!r}"
