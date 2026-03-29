⭐ 1. GitHub Actions CI Pipeline
This pipeline validates:

plugin structure

plugin loading

unit tests

Python packaging integrity

Code
.github/workflows/ci.yml
yaml
name: Forensic Suite CI

on:
  push:
    branches: [ dev, main, feature/* ]
  pull_request:
    branches: [ dev, main ]

jobs:
  build-test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.runtime.txt
          pip install pytest build asyncpg pyyaml

      - name: Validate plugins
        run: |
          python tools/validate_plugins.py

      - name: Run unit tests
        run: |
          pytest -q

      - name: Build wheel
        run: |
          python -m build

      - name: Verify wheel contents
        run: |
          ls -R dist
This gives you:

plugin validation

test execution

wheel build

artifact inspection

All before merging.

⭐ 2. Plugin Documentation Page
Place this under:

Code
docs/plugins.md
markdown
# Forensic Suite v2 — Plugin System

The Forensic Suite plugin system provides a modular way to extend tracing capabilities for new blockchains. Each plugin lives under:

forensic_suite_v2/plugins/<chain>/plugin.py

Code

## Plugin Structure

Each plugin must define a class named `Plugin` that implements:

- `name` — the chain identifier (e.g., "btc", "eth", "tron")
- `description` — human-readable description
- `trace(target=None)` — the tracing entrypoint

### Example Plugin

```python
class <CHAIN>Plugin:
    name = "<chain>"
    description = "<CHAIN> tracer plugin"

    def trace(self, target=None):
        return f"[<CHAIN>] Trace invoked. Target={target!r}"


class Plugin(<CHAIN>Plugin):
    pass
Plugin Loader Behavior
The loader:

discovers all modules under plugins/

imports <module>.plugin

loads the Plugin class

validates required attributes

filters by enabled chains (from indexer.yaml)

logs warnings for invalid plugins

Adding a New Plugin
Create folder:

Code
forensic_suite_v2/plugins/<chain>/
Add plugin.py using the template above.

Add chain configuration to config/indexer.yaml:

yaml
<chain>:
  enabled: true
Run validator:

Code
python tools/validate_plugins.py
Run unit tests:

Code
pytest -q
Commit and push.

CI Validation
GitHub Actions automatically:

validates plugin structure

runs unit tests

builds the wheel

Plugins must pass validation before merging.

⭐ 3. Plugin Generator Script
This script creates a new plugin folder, template, and registers it in the config.

Place this under:

Code
tools/create_plugin.py
python
import os
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
PLUGIN_DIR = ROOT / "forensic_suite_v2" / "plugins"
CONFIG_PATH = ROOT / "forensic_suite_v2" / "config" / "indexer.yaml"

PLUGIN_TEMPLATE = """\
class {CHAIN_CAP}Plugin:
    name = "{chain}"
    description = "{CHAIN_CAP} tracer plugin"

    def trace(self, target=None):
        return f"[{CHAIN_CAP}] Trace invoked. Target={{target!r}}"


class Plugin({CHAIN_CAP}Plugin):
    pass
"""

def create_plugin(chain: str):
    chain = chain.lower()
    chain_cap = chain.upper()

    # Create plugin directory
    target_dir = PLUGIN_DIR / chain
    target_dir.mkdir(parents=True, exist_ok=True)

    # Write plugin.py
    plugin_file = target_dir / "plugin.py"
    plugin_file.write_text(
        PLUGIN_TEMPLATE.format(chain=chain, CHAIN_CAP=chain_cap),
        encoding="utf-8"
    )

    print(f"Created plugin: {plugin_file}")

    # Update indexer.yaml
    if CONFIG_PATH.exists():
        cfg = yaml.safe_load(CONFIG_PATH.read_text())
        if chain not in cfg:
            cfg[chain] = {"enabled": False}
            CONFIG_PATH.write_text(yaml.safe_dump(cfg), encoding="utf-8")
            print(f"Added '{chain}' to indexer.yaml (disabled by default).")
        else:
            print(f"'{chain}' already exists in indexer.yaml.")
    else:
        print("WARNING: indexer.yaml not found; cannot update config.")

    print("Done.")


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("Usage: python tools/create_plugin.py <chain>")
        sys.exit(1)

    create_plugin(sys.argv[1])
Usage:

Code
python tools/create_plugin.py solana
This will:

create plugins/solana/plugin.py

add Solana to indexer.yaml

generate a valid plugin class
