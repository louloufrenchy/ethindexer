┌──────────────────────────────────────────────────────────────┐
│                      Repo A (Authoritative)                  │
│        F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root │
│                     \forensic_suite_v2\                      │
└──────────────────────────────────────────────────────────────┘
                               │
                               │  (mapping CSV generated separately)
                               ▼
                 F:\tools\repo_mapping_suite.csv
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                    Sync‑DevTrees.ps1 (Proposal)              │
│  • Reads mapping CSV                                         │
│  • Applies suite‑only exclusions                             │
│  • Reports: Extra / Missing / Drift                          │
│  • Makes NO changes                                          │
└──────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                Sync‑DevTrees.DryRun.ps1 (Preview)             │
│  • Prints EXACT commands Apply mode will run                  │
│  • Shows deletions, copies, overwrites                        │
│  • Makes NO changes                                           │
└──────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                Sync‑DevTrees.Apply.ps1 (Apply)                │
│  1. Runs DryRun internally                                    │
│  2. Prompts for confirmation                                  │
│  3. Creates timestamped backup:                               │
│       F:\tools\RepoB_Backups\RepoB_YYYYMMDD_HHMMSS\           │
│  4. Deletes extra files                                       │
│  5. Copies missing files                                      │
│  6. Overwrites drift                                          │
│  • Only suite subtree is modified                             │
└──────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                Repo B (Deployable Mirror)                     │
│        F:\DEVELOPMENT\Repo_B\forensic_suite_v2\forensic_suite_v2\    │
└──────────────────────────────────────────────────────────────┘
                               │
                               │
                               ├───────────────► (Optional) Rollback
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│             Sync‑DevTrees.Rollback.ps1 (Restore)               │
│  • Lists available backups                                     │
│  • Requires explicit selection                                 │
│  • Requires confirmation                                       │
│  • Restores ONLY suite subtree                                 │
│  • Leaves top‑level Repo B scripts untouched                   │
└──────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│             Sync‑DevTrees.Validate.ps1 (Integrity)            │
│  • Compares Repo A suite ↔ Repo B suite                       │
│  • Uses SHA256 hashes                                         │
│  • Reports: Missing / Extra / Drift                           │
│  • Confirms perfect mirror                                    │
└──────────────────────────────────────────────────────────────┘
