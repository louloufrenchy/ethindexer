from forensic_suite_v2.plugins.btc.plugin import BTCPlugin
from forensic_suite_v2.plugins.eth.plugin import ETHPlugin
from forensic_suite_v2.plugins.tron.plugin import TRONPlugin
from forensic_suite_v2.plugins.custom.plugin import CustomPlugin


def load_plugins(engine):
    """
    Load all chain plugins into the engine.
    """
    plugins = [
        BTCPlugin(),
        ETHPlugin(),
        TRONPlugin(),
        CustomPlugin(),
    ]

    for plugin in plugins:
        engine.register_plugin(plugin)

    return engine.plugins
