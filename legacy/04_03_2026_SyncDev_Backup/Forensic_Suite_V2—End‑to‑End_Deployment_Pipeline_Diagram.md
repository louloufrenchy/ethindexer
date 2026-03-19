┌──────────────────────────────────────────────────────────────────────────────┐
│                           REPO A — AUTHORITATIVE                             │
│        F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\                │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ forensic_suite_v2\  (REAL SOURCE CODE)                               │   │
│   │   • btc_indexer\                                                     │   │
│   │   • eth_indexer\                                                     │   │
│   │   • tron_indexer\                                                    │   │
│   │   • dashboards\                                                      │   │
│   │   • tools\                                                           │   │
│   │   • scripts\ (install_services.ps1, start_all_indexers.py, etc.)     │   │
│   │   • gui\                                                             │   │
│   │   • plugins\                                                         │   │
│   │   • config\                                                          │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ scripts\ (automation)                                                 │   │
│   │   • Sync-DevTrees.ps1 (proposal)                                      │   │
│   │   • Sync-DevTrees.DryRun.ps1                                          │   │
│   │   • Sync-DevTrees.Apply.ps1                                           │   │
│   │   • Sync-DevTrees.Rollback.ps1                                        │   │
│   │   • Sync-DevTrees.Validate.ps1                                        │   │
│   │   • forensic_suite_repo_mapping.ps1                                   │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

                                      │
                                      │  Sync-DevTrees.Apply.ps1
                                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                           REPO B — DEPLOYABLE MIRROR                         │
│                        F:\DEVELOPMENT\Repo_B\forensic_suite_v2\                     │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ forensic_suite_v2\  (MIRRORED SUITE)                                  │   │
│   │   • Perfect byte-for-byte mirror of Repo A suite                      │   │
│   │   • No egg-info, no drift, no stale files                             │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ Top-level deployment scripts (PRESERVED)                              │   │
│   │   • deploy_suite.ps1                                                  │   │
│   │   • build_and_deploy_all.ps1                                          │   │
│   │   • healthcheck.ps1                                                   │   │
│   │   • merge_suite.ps1                                                   │   │
│   │   • post_deploy_verification.ps1                                      │   │
│   │   • pre_deploy_validator.ps1                                          │   │
│   │   • rollback.ps1                                                      │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   Backups: F:\tools\RepoB_Backups\RepoB_YYYYMMDD_HHMMSS\                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

                                      │
                                      │  Deploy-ForensicSuite.psm1
                                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                           HOST DEPLOYMENT PIPELINE                           │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ 1. Pre-flight validation                                              │   │
│   │    • validate_remote_host.ps1                                         │   │
│   │    • env.json + tracer_v2.yaml loaded                                 │   │
│   │    • Python runtime verified                                           │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ 2. Copy Repo B suite → Host                                           │   │
│   │    • SCP or file copy                                                 │   │
│   │    • Host receives:                                                   │   │
│   │         C:\forensic_suite_v2_blue\forensic_suite_v2\                  │   │
│   │         C:\forensic_suite_v2_green\forensic_suite_v2\                 │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ 3. Virtual environment creation                                       │   │
│   │    • python -m venv venv                                              │   │
│   │    • pip install -r requirements.txt                                  │   │
│   │    • pip install forensic_suite_v2-0.1.2.whl (if installer payload)   │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ 4. Blue/Green slot switching                                          │   │
│   │    • Active symlink: C:\forensic_suite_v2 → C:\forensic_suite_v2_blue │   │
│   │    • Deploy new version to green                                      │   │
│   │    • Health check green                                               │   │
│   │    • Switch symlink to green                                          │   │
│   │    • Old blue becomes rollback slot                                   │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ 5. Service installation (install_services.ps1)                        │   │
│   │    • btc_indexer                                                      │   │
│   │    • eth_indexer                                                      │   │
│   │    • tron_indexer                                                     │   │
│   │    • dashboard_service                                                │   │
│   │    • All services:                                                    │   │
│   │         sc.exe create <svc> binPath="venv\python.exe script.py"       │   │
│   │         sc.exe failure <svc> actions=restart/5000                     │   │
│   │         Start-Service <svc>                                           │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │ 6. Post-deploy validation                                             │   │
│   │    • healthcheck.ps1                                                  │   │
│   │    • operator_console.ps1                                             │   │
│   │    • Grafana dashboards connected                                     │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

                                      │
                                      │  Rollback-Single / Rollback-BlueGreen
                                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                           ROLLBACK / RECOVERY PATH                           │
│                                                                              │
│   • Switch symlink back to previous slot (blue or green)                     │
│   • Restore Repo B from backup if needed                                     │
│   • Reinstall services if required                                           │
│   • Re-run health checks                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
