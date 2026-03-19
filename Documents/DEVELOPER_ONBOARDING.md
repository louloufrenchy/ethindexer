# Developer Onboarding Guide — Forensic Suite v2

Welcome to the forensic suite development environment.  
This guide will get you fully operational in under 10 minutes.

---

## 1. Clone the Repository

git clone https://github.com/louloufrenchy/ethindexer.git
cd forensic_suite_v2


---

## 2. Create a Virtual Environment

python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -e .


---

## 3. Install Developer Tools

pip install flake8 black pytest rich


---

## 4. Understand the Architecture

- **core/** → engine, plugin loader, abstractions  
- **plugins/** → chain-specific plugin modules  
- **btc_indexer/**, **eth_indexer/**, **tron_indexer/** → chain indexers  
- **dashboards/** → Grafana + PowerShell dashboards  
- **scripts/** → operational scripts  
- **tools/** → environment loaders, validators  
- **chains.json** → chain manifest  

---

## 5. Running Indexers

Start all chains:

python scripts/start_all_indexers.py


Start a single chain:

python tron_indexer/services/run_tron_indexer_v2.py


---

## 6. Code Style

- Use **Black** for formatting
- Use **flake8** for linting
- Keep modules small and composable
- Prefer dependency injection over global state

---

## 7. Pull Requests

- Create a feature branch
- Ensure CI passes
- Add tests where relevant
- Keep commits atomic

---

## 8. Troubleshooting

### Virtual environment not activating  
Ensure PowerShell execution policy allows scripts:

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser


### Database connection issues  
Check `.env` and `tools/loadforensicenv.ps1`.

---

Welcome aboard — build boldly.

