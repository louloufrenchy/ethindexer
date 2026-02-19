from forensic_suite_v2.plugins.eth.plugin import EthPlugin
from forensic_suite_v2.plugins.tron.plugin import TronPlugin
from forensic_suite_v2.plugins.btc.plugin import BtcPlugin

class ETHPlugin:
    name = "eth"
    description = "Ethereum tracer plugin"

    def trace(self, target=None):
        # Placeholder implementation – extend with real ETH tracing
        return f"[ETH] Trace invoked. Target={target!r}"
