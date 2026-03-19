from pathlib import Path
import logging
import sys
import subprocess

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
# 1. Detect installer root
# ------------------------------------------------------------
def _find_install_root() -> Path:
    """
    Walk upwards until we find a folder that looks like the installer root:
    must contain 'dashboards' and 'scripts' directories.
    """
    p = Path(__file__).resolve()
    for parent in p.parents:
        if (parent / "dashboards").is_dir() and (parent / "scripts").is_dir():
            return parent
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
# 2. Force PowerShell 5.1 for all script launches
# ------------------------------------------------------------
POWERSHELL_51 = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"


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
# 5. Main Cockpit Window
# ------------------------------------------------------------
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Forensic Suite v2 – Cockpit")
        icon_path = INSTALL_ROOT / "gui" / "icons" / "forensic.ico"
        if icon_path.exists():
            self.setWindowIcon(QIcon(str(icon_path)))

        self.engine = Engine()

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
        indexers_menu = menubar.addMenu("Indexers")
        tracer_menu = menubar.addMenu("Tracer")

        validate_action = file_menu.addAction("Validate Installation")
        validate_action.triggered.connect(self._validate_installation)

        # Dashboards
        for label, script in [
            ("BTC Dashboard", "btc_dashboard.ps1"),
            ("ETH Dashboard", "eth_dashboard.ps1"),
            ("TRON Dashboard", "tron_dashboard.ps1"),
            ("Multi-Chain Dashboard", "multi_chain_dashboard.ps1"),
        ]:
            action = dashboards_menu.addAction(label)
            action.triggered.connect(
                lambda _, s=script: self._run_ps_script("dashboards", s)
            )

        # Indexers
        for chain in ["btc", "eth", "tron"]:
            action = indexers_menu.addAction(f"Run {chain.upper()} Indexer")
            action.triggered.connect(lambda _, c=chain: self._run_indexer(c))

        run_all_action = indexers_menu.addAction("Run All Indexers")
        run_all_action.triggered.connect(self._run_all_indexers)

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

        layout.addWidget(QLabel("Available Tracers:"))
        for name, plugin in self.engine.plugins.items():
            btn = QPushButton(f"Run tracer: {name.upper()}")
            btn.clicked.connect(lambda _, c=name: self._run_tracer(c))
            layout.addWidget(btn)

        layout.addWidget(QLabel("Dashboards:"))
        for label, script in [
            ("BTC Dashboard", "btc_dashboard.ps1"),
            ("ETH Dashboard", "eth_dashboard.ps1"),
            ("TRON Dashboard", "tron_dashboard.ps1"),
            ("Multi-Chain Dashboard", "multi_chain_dashboard.ps1"),
        ]:
            btn = QPushButton(label)
            btn.clicked.connect(lambda _, s=script: self._run_ps_script("dashboards", s))
            layout.addWidget(btn)

        layout.addWidget(QLabel("Indexers:"))
        row = QHBoxLayout()
        for chain in ["btc", "eth", "tron"]:
            btn = QPushButton(f"{chain.upper()} Indexer")
            btn.clicked.connect(lambda _, c=chain: self._run_indexer(c))
            row.addWidget(btn)
        layout.addLayout(row)

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
    # Script Launchers (FORCE POWERSHELL 5.1)
    # --------------------------------------------------------
    def _run_ps_script(self, subdir: str, filename: str):
        script = INSTALL_ROOT / subdir / filename
        logging.info(f"Launching PowerShell script: {script}")

        if not script.exists():
            msg = f"Script not found: {script}"
            logging.error(msg)
            QMessageBox.warning(self, "Script not found", msg)
            return

        subprocess.Popen([
            POWERSHELL_51, "-ExecutionPolicy", "Bypass",
            "-File", str(script)
        ])

    def _run_indexer(self, chain: str):
        script = INSTALL_ROOT / "scripts" / f"run_{chain}_indexer.ps1"
        logging.info(f"Launching indexer script: {script}")

        if not script.exists():
            msg = f"Indexer script not found: {script}"
            logging.error(msg)
            QMessageBox.warning(self, "Indexer not found", msg)
            return

        subprocess.Popen([
            POWERSHELL_51, "-ExecutionPolicy", "Bypass",
            "-File", str(script)
        ])

    def _run_all_indexers(self):
        script = INSTALL_ROOT / "scripts" / "run_all_indexers.ps1"
        logging.info(f"Launching all-indexers script: {script}")

        if not script.exists():
            msg = f"Run-all script not found: {script}"
            logging.error(msg)
            QMessageBox.warning(self, "Script not found", msg)
            return

        subprocess.Popen([
            POWERSHELL_51, "-ExecutionPolicy", "Bypass",
            "-File", str(script)
        ])

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
        issues = []

        for fname in [
            "btc_dashboard.ps1",
            "eth_dashboard.ps1",
            "tron_dashboard.ps1",
            "multi_chain_dashboard.ps1",
        ]:
            path = INSTALL_ROOT / "dashboards" / fname
            if not path.exists():
                issues.append(f"Missing dashboard: {path}")

        for fname in [
            "run_btc_indexer.ps1",
            "run_eth_indexer.ps1",
            "run_tron_indexer.ps1",
            "run_all_indexers.ps1",
        ]:
            path = INSTALL_ROOT / "scripts" / fname
            if not path.exists():
                issues.append(f"Missing indexer script: {path}")

        if not self.engine.plugins:
            issues.append("No plugins registered in Engine.")

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
                "All required dashboards, scripts, and plugins are present.",
            )
            self.statusBar().showMessage("Validation successful", 5000)

if __name__ == "__main__":
    launch_gui()
