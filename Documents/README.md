# Forensic Suite v2

A unified, multi‑chain forensic analysis platform supporting **Bitcoin (BTC)**, **Ethereum (ETH)**, and **TRON**.  
This suite provides indexers, dashboards, plugins, orchestration tools, and a modular engine for investigator‑grade blockchain forensics.

---

## 🚀 Features

- **Multi‑chain indexers** (BTC, ETH, TRON)
- **Unified orchestration engine**
- **Plugin‑based architecture**
- **Grafana dashboards**
- **CLI tools for tracing and analysis**
- **Modular configuration system**
- **Environment validation and bootstrap scripts**
- **GitHub Actions CI pipeline**
- **Copilot agent instruction file**

---

## 📁 Repository Structure

forensic_suite_v2/
│
├── btc_indexer/
├── eth_indexer/
├── tron_indexer/
│
├── core/               # Engine, plugin loader, abstractions
├── plugins/            # Chain-specific plugins
├── cli/                # Command-line interface
├── dashboards/         # Grafana + PowerShell dashboards
├── tools/              # Env loaders, validators
├── scripts/            # Operational scripts
├── config/             # YAML configs
│
├── chains.json         # Unified chain manifest
├── pyproject.toml      # Packaging definition
├── COPILOT_INSTRUCTIONS.md
└── README.md


---

## 🧩 Requirements

- Python 3.11+
- PostgreSQL 14+
- PowerShell 7+
- Grafana (optional)
- Windows or Linux

---

## 🛠 Installation

python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -e .


---

## ▶️ Running Indexers

Start all enabled chains:

python scripts/start_all_indexers.py


Start a single chain:

python tron_indexer/services/run_tron_indexer_v2.py


---

## 🧪 Development

Run linting:

flake8 .


Run tests (if added):

pytest


---

## 🤝 Contributing

Pull requests are welcome.  
Please ensure your code is modular, typed, and follows the suite’s architecture.

---

## 📄 License

MIT License (or your preferred license)



