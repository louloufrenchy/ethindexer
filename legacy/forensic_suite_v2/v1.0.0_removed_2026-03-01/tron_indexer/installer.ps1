# -----------------------------
# TRON Indexer Windows Installer
# -----------------------------

Write-Host "Starting TRON Indexer installation..."

# 1. Create folder structure
$root = "C:\tron_indexer"
$dirs = @(
    "$root\config",
    "$root\logs",
    "$root\db",
    "$root\services",
    "$root\api"
)

foreach ($d in $dirs) {
    if (!(Test-Path $d)) {
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}

# 2. Install Python (if missing)
if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Python not found. Please install Python 3.11+ manually."
    exit
}

# 3. Install Python dependencies
pip install python-dotenv pandas requests openpyxl playwright selenium undetected-chromedriver tdqm pyvis base58 py4cytoscape[all] flask eth-utils asyncpg pydantic network rich fastapi uvicorn PySimpleGUI py2cytoscape graphviz

# 4. Copy config templates
Copy-Item ".\config\indexer.yaml" "$root\config\indexer.yaml" -Force

# 5. Register Windows Services using NSSM
$nssm = "C:\nssm\nssm.exe"

# Indexer
& $nssm install TronIndexerService "python.exe" "$root\services\run_indexer.py"
& $nssm set TronIndexerService AppDirectory $root
& $nssm set TronIndexerService Start SERVICE_AUTO_START

# Token Registry Daemon
& $nssm install TronTokenRegistry "python.exe" "$root\services\token_daemon.py"
& $nssm set TronTokenRegistry AppDirectory $root
& $nssm set TronTokenRegistry Start SERVICE_AUTO_START

# API Service
& $nssm install TronIndexerAPI "python.exe" "$root\api\run_api.py"
& $nssm set TronIndexerAPI AppDirectory $root
& $nssm set TronIndexerAPI Start SERVICE_AUTO_START

Write-Host "Installation complete."
