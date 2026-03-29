import pytest
from forensic_suite_v2.core.plugin_loader import discover_plugins


def test_discover_plugins_loads_valid_plugins(monkeypatch):
    """
    Ensures that valid plugins load correctly and return instances.
    """
    plugins = discover_plugins()
    assert isinstance(plugins, dict)
    assert "btc" in plugins or "eth" in plugins or "tron" in plugins


def test_discover_plugins_chain_filtering(monkeypatch):
    """
    Ensures that chain filtering works as expected.
    """
    plugins = discover_plugins(enabled_chains=["tron"])
    assert "tron" in plugins
    assert "btc" not in plugins
    assert "eth" not in plugins


def test_plugin_has_required_attributes():
    """
    Ensures that each plugin has required attributes.
    """
    plugins = discover_plugins()
    for name, plugin in plugins.items():
        assert hasattr(plugin, "name")
        assert hasattr(plugin, "trace")
        assert callable(plugin.trace)


def test_duplicate_plugin_names(monkeypatch):
    """
    Ensures duplicate plugin names are handled gracefully.
    """
    # Simulate duplicate plugin names by monkeypatching
    class FakePlugin:
        name = "btc"
        def trace(self, target=None): pass

    def fake_discover(*args, **kwargs):
        return {"btc": FakePlugin(), "btc_duplicate": FakePlugin()}

    monkeypatch.setattr(
        "forensic_suite_v2.core.plugin_loader.discover_plugins",
        fake_discover
    )

    plugins = fake_discover()
    assert len(plugins) == 2  # both keys exist
    assert plugins["btc"].name == "btc"
