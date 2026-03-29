from pathlib import Path
import logging
import sys
import subprocess
import yaml

from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout,
    QHBoxLayout, QPushButton, QLabel, QMenuBar, QStatusBar,
    QComboBox, QLineEdit, QTextEdit, QDialog, QMessageBox
)
from PySide6.QtGui import QIcon
from PySide6.QtCore import Qt

from forensic_suite_v2.core.engine import Engine
from forensic_suite_v2.core.plugin_loader import discover_plugins

# ------------------------------------------------------------
# 1. Detect installer root (site-packages forensic_suite_v2)
# ------------------------------------------------------------
def _find_install_root() -> Path:
    """
    Walk upwards until we find a folder that looks like the package root:
    must contain 'dashboards' and 'scripts' directories.
    """
    p = Path(__file__).resolve()
    for parent in p.parents:
        if (parent / "dashboards").is_dir() and (parent / "scripts").is_dir():
            return parent
    # Fallback: three levels up (repo layout)
    return Path(__file__).resolve().parents[3]


INSTALL_ROOT = _find_install_root()
LOG_DIR = INSTALL_ROOT / "logs"
LOG_DIR.mkdir(exist_ok=True)

logging.basicConfig(
    filename=LOG_DIR / "gui.log",
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)


# ------------------------------------------------------------
# 2. Config / chain detection
# ------------------------------------------------------------
def _load_indexer_config() -> dict:
    """
    Load indexer.yaml from the installed package root.
    """
    cfg_path = INSTALL_ROOT / "config" / "indexer.yaml"
    if not cfg_path.exists():
        raise FileNotFoundError(f"Indexer config not found: {cfg_path}")
    with open(cfg_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _get_enabled_chains(cfg: dict) -> list[str]:
    """
    Return list of enabled chains based on indexer.yaml.
    If none explicitly enabled, fall back to all known chains.
    """
    chains: list[str] = []
    for chain in ["btc", "eth", "tron"]:
        section = cfg.get(chain)
        if section and bool(section.get("enabled", False)):
            chains.append(chain)
    if not chains:
        chains = ["btc", "eth", "tron"]
    return chains


# ------------------------------------------------------------
# 3. Launch GUI
# ------------------------------------------------------------
def launch_gui():
    app = QApplication(sys.argv)
    app.setApplicationName("Forensic Suite v2")

    window = MainWindow()
    window.show()
    sys.exit(app.exec())


# ------------------------------------------------------------
# 4. Tracer Console
# ------------------------------------------------------------
class TracerConsole(QDialog):
    def __init__(self, engine: Engine, parent=None):
        super().__init__(parent)
        self.engine = engine
        self.setWindowTitle("Tracer Console")
        self.resize(600, 400)

        layout = QVBoxLayout()

        self.chain_combo = QComboBox()
        self.chain_combo.addItems(sorted(self.engine.plugins.keys()))
        layout.addWidget(QLabel("Chain:"))
        layout.addWidget(self.chain_combo)

        self.target_edit = QLineEdit()
        layout.addWidget(QLabel("Target (address/tx/etc.):"))
        layout.addWidget(self.target_edit)

        self.output = QTextEdit()
        self.output.setReadOnly(True)
        layout.addWidget(QLabel("Output:"))
        layout.addWidget(self.output)

        run_btn = QPushButton("Run Trace")
        run_btn.clicked.connect(self._run_trace)
        layout.addWidget(run_btn)

        self.setLayout(layout)

    def _run_trace(self):
        chain = self.chain_combo.currentText()
        target = self.target_edit.text().strip() or None

        try:
            logging.info(f"TracerConsole: tracing chain={chain}, target={target}")
            result = self.engine.trace(chain, target)
            if result is None:
                result = f"Trace completed for {chain} (no return value)."
            self.output.append(str(result))
        except Exception as e:
            msg = f"Error during trace: {e}"
            logging.exception(msg)
            self.output.append(msg)


# ------------------------------------------------------------
# 5. Main Cockpit Window (chain-aware, Python dashboards)
# ------------------------------------------------------------
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Forensic Suite v2 – Cockpit")
        icon_path = INSTALL_ROOT / "gui" / "icons" / "forensic.ico"
        if icon_path.exists():
            self.setWindowIcon(QIcon(str(icon_path)))

        # Load config and detect enabled chains
        try:
            self._cfg = _load_indexer_config()
        except Exception as exc:
            logging.exception("Failed to load indexer config")
            QMessageBox.critical(self, "Config error", str(exc))
            self._cfg = {}

        self.enabled_chains = _get_enabled_chains(self._cfg)

        # Engine + plugin filtering by enabled chains
        self.engine = Engine()
        self.engine.plugins = discover_plugins(enabled_chains=self.enabled_chains)
        if self.engine.plugins:
            self.engine.plugins = {
                name: plugin
                for name, plugin in self.engine.plugins.items()
                if name in self.enabled_chains
            }

        self._build_menu()
        self._build_central()
        self._build_status()

        self.resize(800, 600)

    # --------------------------------------------------------
    # Menu
    # --------------------------------------------------------
    def _build_menu(self):
        menubar = QMenuBar(self)

        file_menu = menubar.addMenu("File")
        dashboards_menu = menubar.addMenu("Dashboards")
        tracer_menu = menubar.addMenu("Tracer")

        validate_action = file_menu.addAction("Validate Installation")
        validate_action.triggered.connect(self._validate_installation)

        # Only the unified multi-chain dashboard
        multi_chain_action = dashboards_menu.addAction("Multi-Chain Dashboard")
        multi_chain_action.triggered.connect(
            lambda _: self._run_python_module("forensic_suite_v2.dashboards.forensic_dashboard_gui")
        )

        tracer_action = tracer_menu.addAction("Open Tracer Console")
        tracer_action.triggered.connect(self._open_tracer_console)

        self.setMenuBar(menubar)

    # --------------------------------------------------------
    # Central Panel
    # --------------------------------------------------------
    def _build_central(self):
        central = QWidget()
        layout = QVBoxLayout()
        layout.setAlignment(Qt.AlignTop)

        title = QLabel("Forensic Suite v2 – Multi-Chain Cockpit")
        title.setStyleSheet("font-size: 18px; font-weight: bold;")
        layout.addWidget(title)

        validate_btn = QPushButton("Validate Installation")
        validate_btn.clicked.connect(self._validate_installation)
        layout.addWidget(validate_btn)

        # Tracers (from plugins, filtered by enabled chains)
        layout.addWidget(QLabel("Available Tracers:"))
        if self.engine.plugins:
            for name, plugin in self.engine.plugins.items():
                btn = QPushButton(f"Run tracer: {name.upper()}")
                btn.clicked.connect(lambda _, c=name: self._run_tracer(c))
                layout.addWidget(btn)
        else:
            layout.addWidget(QLabel("No tracers available (no plugins loaded)."))

        # Dashboards (Python, chain-aware)
        layout.addWidget(QLabel("Dashboards:"))

        # Only the unified multi-chain dashboard
        btn_multi = QPushButton("Multi-Chain Dashboard")
        btn_multi.clicked.connect(
            lambda _: self._run_python_module("forensic_suite_v2.dashboards.forensic_dashboard_gui")
        )
        layout.addWidget(btn_multi)

        layout.addWidget(QLabel("Indexers:"))
        layout.addWidget(QLabel("Indexers are managed as Windows services on each host."))

        central.setLayout(layout)
        self.setCentralWidget(central)

    # --------------------------------------------------------
    # Status Bar
    # --------------------------------------------------------
    def _build_status(self):
        status = QStatusBar()
        status.showMessage("Ready")
        self.setStatusBar(status)

    # --------------------------------------------------------
    # Launch helpers (Python modules, not PowerShell)
    # --------------------------------------------------------
    def _run_python_module(self, module: str):
        """
        Launch a Python module in a separate process using the same interpreter.
        """
        logging.info(f"Launching Python module: {module}")
        try:
            subprocess.Popen([sys.executable, "-m", module])
        except Exception as exc:
            msg = f"Failed to launch module {module}: {exc}"
            logging.exception(msg)
            QMessageBox.critical(self, "Launch error", msg)

    # --------------------------------------------------------
    # Tracer + Validation
    # --------------------------------------------------------
    def _run_tracer(self, chain: str):
        try:
            logging.info(f"GUI tracer button: chain={chain}")
            self.engine.trace(chain)
            self.statusBar().showMessage(f"Trace started for {chain}", 3000)
        except Exception as e:
            msg = f"Error running tracer for {chain}: {e}"
            logging.exception(msg)
            QMessageBox.critical(self, "Tracer error", msg)

    def _open_tracer_console(self):
        dlg = TracerConsole(self.engine, self)
        dlg.exec()

    def _validate_installation(self):
        issues: list[str] = []

        # Config
        cfg_path = INSTALL_ROOT / "config" / "indexer.yaml"
        if not cfg_path.exists():
            issues.append(f"Missing indexer config: {cfg_path}")

        # Dashboards (Python)
        dashboards = [
            ("Multi-Chain Dashboard", INSTALL_ROOT / "dashboards" / "forensic_dashboard_gui.py"),
        ]

        for label, path in dashboards:
            if not path.exists():
                issues.append(f"Missing dashboard ({label}): {path}")

        # Plugins
        if not self.engine.plugins:
            issues.append("No plugins registered in Engine (no tracers available).")

        if issues:
            logging.warning("Validation issues:\n" + "\n".join(issues))
            QMessageBox.warning(
                self,
                "Validation failed",
                "Some issues were found:\n\n" + "\n".join(issues),
            )
            self.statusBar().showMessage("Validation failed – see details", 5000)
        else:
            logging.info("Validation successful.")
            QMessageBox.information(
                self,
                "Validation successful",
                "All required dashboards, config, and plugins are present.",
            )
            self.statusBar().showMessage("Validation successful", 5000)


if __name__ == "__main__":
    launch_gui()
