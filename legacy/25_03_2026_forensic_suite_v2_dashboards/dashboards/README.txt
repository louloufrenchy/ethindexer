Forensic Suite Production Dashboard Pack

Files:
- dashboard_common.py
- forensic_dashboard_cli.py
- forensic_dashboard_gui.py
- multi_chain_dashboard.ps1
- launch_dashboard_gui.ps1

Recommended deployment path:
C:\forensic_suite_v2\forensic_suite_v2\dashboards\

What this fixes:
- removes broken Python import lines from .ps1 usage
- uses unified config path:
  C:\forensic_suite_v2\forensic_suite_v2\config\indexer.yaml
- reads postgres config from cfg["postgres"]
- uses unified index_checkpoint table
- supports indexer head lookup from ingestion_metrics or indexer_metrics
- provides both CLI and GUI dashboards

Run:
CLI:
  powershell -ExecutionPolicy Bypass -File .\multi_chain_dashboard.ps1

GUI:
  powershell -ExecutionPolicy Bypass -File .\launch_dashboard_gui.ps1
