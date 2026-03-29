import sys
import logging
from forensic_suite_v2.core.plugin_loader import discover_plugins

logging.basicConfig(level=logging.INFO, format="%(message)s")


def main():
    logging.info("Validating plugins...")

    plugins = discover_plugins()

    if not plugins:
        logging.error("❌ No plugins found.")
        sys.exit(1)

    errors = []

    for name, plugin in plugins.items():
        if not hasattr(plugin, "name"):
            errors.append(f"Plugin '{name}' missing attribute: name")
        if not hasattr(plugin, "trace"):
            errors.append(f"Plugin '{name}' missing method: trace()")
        if not callable(plugin.trace):
            errors.append(f"Plugin '{name}' has non-callable trace()")

    if errors:
        logging.error("❌ Plugin validation failed:")
        for e in errors:
            logging.error(f"  - {e}")
        sys.exit(1)

    logging.info("✅ All plugins validated successfully.")
    sys.exit(0)


if __name__ == "__main__":
    main()
