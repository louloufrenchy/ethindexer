
🟦 Side‑by‑Side Responsibility Matrix
ForensicSuite.Validation.psm1 vs scripts\Invoke‑ForensicRelease.ps1
Responsibility						ForensicSuite.Validation.psm1 (Module)			Invoke‑ForensicRelease.ps1 (Script)
Loaded into memory via loadfs		✔ Yes											✘ No
Defines PowerShell functions		✔ Yes											✘ No
Top‑level executable					✘ No											✔ Yes
Controls orchestration flow			✔ Yes											✔ Yes (but only within script scope)
Calls other scripts					✔ Yes											✔ Yes
Contains wheel install logic		✘ No											✔ Yes
Contains $latestWheel throw			✘ No											✔ Yes
Copied into installer payload		✘ No											✔ Yes
Executed on remote host				✘ No											✔ Yes (via payload)
Controls rollback					✔ Yes											✔ Yes (delegated)
Controls cluster logic				✔ Yes											✘ No
Controls remote runtime preparation	✔ Yes (Invoke-RemoteRuntimePrepare)			✘ No
Controls build pipeline				✔ Yes											✔ Yes (when invoked)
Controls payload refresh			✔ Yes											✔ Yes (when invoked)
Defines helper functions			✔ Yes											✔ Yes (local to script)
Authoritative source of truth		✔ Yes (logic)									✔ Yes (execution)
Where drift caused the abort		✘ No											✔ Yes (payload copy was stale)

In one sentence:
The module is the conductor.

The script is the worker.

The payload copy is the worker that actually gets deployed.

🟦 Full Architecture Diagram
Flow: Module → Script → Payload → Remote Host
Code
┌──────────────────────────────────────────────────────────────┐
│                    1. Module Loaded (loadfs)                  │
│                ForensicSuite.Validation.psm1                  │
│                                                              │
│  - Defines Invoke-ForensicRelease (function)                 │
│  - Defines Invoke-BuildSuite, Update-InstallerPayload        │
│  - Defines Invoke-DeployHost, Invoke-RemoteRuntimePrepare    │
│  - Controls orchestration, rollback, cluster logic           │
└───────────────┬──────────────────────────────────────────────┘
                │
                │ calls
                ▼
┌──────────────────────────────────────────────────────────────┐
│            2. Local Script Executed by Module                │
│                scripts\Invoke-ForensicRelease.ps1            │
│                                                              │
│  - Implements build + deploy pipeline                        │
│  - Contains wheel install logic                              │
│  - Contains `$latestWheel` throw                             │
│  - Reads payload, deploys to hosts                           │
│  - This is the file YOU patched                              │
└───────────────┬──────────────────────────────────────────────┘
                │
                │ copied by
                ▼
┌──────────────────────────────────────────────────────────────┐
│            3. Installer Payload (runtime bundle)             │
│         installer_payload\scripts\Invoke-ForensicRelease.ps1 │
│                                                              │
│  - This is the version deployed to remote hosts              │
│  - Must match the patched version                            │
│  - Was stale → caused abort                                  │
│  - Now patched → abort gone                                  │
└───────────────┬──────────────────────────────────────────────┘
                │
                │ transferred via SCP
                ▼
┌──────────────────────────────────────────────────────────────┐
│            4. Remote Host Deployment (192.168.0.172)         │
│                                                              │
│  - Payload extracted to C:\forensic_suite_v2                 │
│  - Payload script executed                                   │
│  - Wheel installed                                           │
│  - Runtime prepared                                          │
│  - Services installed via NSSM                               │
│  - GUI + indexers validated                                  │
└──────────────────────────────────────────────────────────────┘
🟦 Why the $latestWheel abort happened

Because the payload copy (step 3) still contained the old double‑quoted throw, even after you patched the script in step 2.

Once patched the authoritative script and refreshed the payload, the abort disappeared

🟦 1. Drift‑Proofing Checklist
A deterministic checklist to ensure Repo A → Repo B → Payload → Host remain in sync.

A. Workspace / Repo Hygiene
[ ] Ensure $Global:PrimaryRoot points to the authoritative Repo A

[ ] Run loadfs to load the correct module version

[ ] Confirm ForensicSuite.Validation.psm1 is the active module

[ ] Verify no stale copies of scripts exist in root (e.g., old Invoke‑ForensicRelease.ps1)

B. Script Drift Prevention
[ ] Patch scripts only in:
F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\scripts\

[ ] Run Update-InstallerPayload after any script change

[ ] Confirm payload copy matches authoritative script:
installer_payload\scripts\…

[ ] Run Get-DeploySuiteSummary → check “Script Drift Status”

C. Wheel / Python Drift Prevention
[ ] Ensure Invoke-BuildSuite produces a fresh wheel in dist\

[ ] Confirm payload wheel matches dist wheel

[ ] Confirm remote host Python version matches expected (Python314)

[ ] Confirm GUI dependencies exist in payload requirements.txt

D. Deployment Drift Prevention
[ ] Run Invoke-DeployPreflight before any deploy

[ ] Confirm installer EXE hash matches expected

[ ] Confirm payload hash matches expected

[ ] Confirm Blue/Green slot contents match payload

[ ] Confirm symlink points to correct slot after deploy

E. Remote Host Drift Prevention
[ ] Confirm C:\forensic_suite_v2 symlink resolves correctly

[ ] Confirm services exist and are running

[ ] Confirm GUI import path works on host

[ ] Confirm runtime requirements installed cleanly

[ ] Confirm no stale directories exist (C:\forensic_suite_v2_blue, green, etc.)

🟦 2. Blue/Green Slot Switching Diagram
Code
                     ┌──────────────────────────────┐
                     │   C:\forensic_suite_v2_blue   │
                     │   (inactive or active slot)   │
                     └───────────────┬──────────────┘
                                     │
                                     │
┌──────────────────────────────┐     │     ┌──────────────────────────────┐
│   C:\forensic_suite_v2       │◄────┼────►│   C:\forensic_suite_v2_green │
│   (symlink → active slot)    │           │   (inactive or active slot)   │
└──────────────────────────────┘           └──────────────────────────────┘
                 ▲
                 │
     During deployment:
     - New payload copied into inactive slot  
     - Validation performed  
     - Symlink switched atomically  
     - Services restarted  
     - Old slot becomes inactive  
Flow Summary
Determine active slot via symlink resolution

Deploy new suite into inactive slot

Validate wheel, requirements, GUI imports

Switch symlink atomically

Restart services

Old slot becomes rollback target

🟦 3. Python Runtime Preparation Flow
(Executed on remote host via Invoke-RemoteRuntimePrepare)

Code
┌──────────────────────────────────────────────┐
│ 1. Validate Python interpreter                │
│    - Check C:\Program Files\Python314\python │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 2. Validate suite root                        │
│    - C:\forensic_suite_v2                     │
│    - requirements.txt                          │
│    - wheel\*.whl                               │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 3. Create runtime directories                 │
│    - C:\forensic_state\{btc,eth,tron}         │
│    - C:\forensic_suite_logs                   │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 4. Upgrade pip/setuptools/wheel               │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 5. Install runtime requirements               │
│    pip install -r requirements.txt            │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 6. Install wheel (if present)                 │
│    pip install --force-reinstall *.whl        │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 7. Install package from suite root            │
│    pip install .                              │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 8. Verify core imports                        │
│    orjson, yaml, prometheus_client            │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 9. Verify GUI imports                         │
│    PySide6, qt_material, qasync, pyqtgraph    │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 10. Verify GUI module import                  │
│     import forensic_suite_v2.gui.app          │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 11. Install services via install_services.ps1 │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 12. Validate services running                 │
│     btc_indexer, eth_indexer, tron_indexer    │
│     forensic_orchestrator                     │
└──────────────────────────────────────────────┘
🟦 4. GUI Import Validation Path
(Ensures GUI is deployable and runnable via python -m)

Code
┌──────────────────────────────────────────────┐
│ 1. Wheel contains GUI package                 │
│    forensic_suite_v2/gui/...                  │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 2. PySide6 + GUI deps installed               │
│    PySide6, qt_material, qasync, pyqtgraph    │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 3. Python import test                         │
│    python -c "import forensic_suite_v2.gui"   │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 4. Module entrypoint exists                   │
│    forensic_suite_v2/gui/__main__.py          │
│    → enables python -m forensic_suite_v2.gui  │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 5. Console script entrypoint                  │
│    forensic-suite-v2-gui → launch_gui()       │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 6. GUI runtime validation                     │
│    import PySide6                             │
│    import forensic_suite_v2.gui.app           │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 7. GUI launch test                            │
│    python -m forensic_suite_v2.gui            │
│    forensic-suite-v2-gui                      │
└──────────────────────────────────────────────┘

🟦 1. Full End‑to‑End Pipeline Diagram
Repo A → Repo B → Build → Payload → Deploy → Runtime → Services
Code
┌──────────────────────────────────────────────────────────────┐
│                        REPO A (Authoritative)                 │
│   F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root       │
│   - Source code (Python, GUI, services)                       │
│   - Scripts (Invoke-ForensicRelease.ps1, Sync-Dev, etc.)      │
│   - build_final.ps1, build_and_deploy.ps1                     │
│   - ForensicSuite.Validation.psm1 (module)                    │
└───────────────┬──────────────────────────────────────────────┘
                │ Sync-DevTrees.FullSuite.ps1
                ▼
┌──────────────────────────────────────────────────────────────┐
│                        REPO B (Runtime Mirror)                │
│   F:\DEVELOPMENT\Repo_B\forensic_suite_v2                            │
│   - Cleaned by Clear-ForensicSuiteAll                         │
│   - Receives synced runtime tree                              │
│   - Used for local testing + installer build                  │
└───────────────┬──────────────────────────────────────────────┘
                │ Invoke-BuildSuite
                ▼
┌──────────────────────────────────────────────────────────────┐
│                        BUILD ARTIFACTS                        │
│   dist\forensic_suite_v2‑X.Y.Z.whl                           │
│   Output\ForensicSuiteV2-Setup.exe                            │
│   logs\BuildSuite_*.log                                       │
└───────────────┬──────────────────────────────────────────────┘
                │ Update-InstallerPayload
                ▼
┌──────────────────────────────────────────────────────────────┐
│                        INSTALLER PAYLOAD                      │
│   installer_payload\                                          │
│     ├── wheel\*.whl                                           │
│     ├── scripts\*.ps1                                         │
│     ├── forensic_suite_v2\ (runtime tree)                     │
│     ├── requirements.txt                                      │
│     └── bootstrap.ps1                                         │
└───────────────┬──────────────────────────────────────────────┘
                │ Invoke-ForensicRelease -DeployOnly
                ▼
┌──────────────────────────────────────────────────────────────┐
│                        REMOTE HOST (e.g., .172)               │
│   C:\forensic_suite_v2_blue                                   │
│   C:\forensic_suite_v2_green                                  │
│   C:\forensic_suite_v2  → symlink to active slot              │
│   Payload extracted into inactive slot                        │
└───────────────┬──────────────────────────────────────────────┘
                │ Invoke-RemoteRuntimePrepare
                ▼
┌──────────────────────────────────────────────────────────────┐
│                        PYTHON RUNTIME PREP                    │
│   - pip install -r requirements.txt                           │
│   - pip install wheel                                         │
│   - pip install . (suite root)                                │
│   - Validate imports (core + GUI)                             │
│   - install_services.ps1                                      │
└───────────────┬──────────────────────────────────────────────┘
                │ NSSM
                ▼
┌──────────────────────────────────────────────────────────────┐
│                        SERVICES INSTALLED                     │
│   btc_indexer                                                 │
│   eth_indexer                                                 │
│   tron_indexer                                                │
│   forensic_orchestrator                                       │
│   → All must be Running                                       │
└──────────────────────────────────────────────────────────────┘
🟦 2. Service Lifecycle Diagram
From installation → startup → monitoring → restart → teardown
Code
┌──────────────────────────────────────────────┐
│ 1. Service Definition (install_services.ps1)  │
│   - nssm install btc_indexer ...              │
│   - nssm install eth_indexer ...              │
│   - nssm install tron_indexer ...             │
│   - nssm install forensic_orchestrator ...    │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 2. Service Installation                       │
│   - Services created in SCM                   │
│   - Startup type: Automatic                   │
│   - Executable: python.exe -m ...             │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 3. Service Startup                            │
│   - NSSM launches python interpreter           │
│   - Logs written to C:\forensic_suite_logs     │
│   - Orchestrator supervises indexers           │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 4. Runtime Monitoring                          │
│   - Get-Service btc_indexer                    │
│   - Orchestrator health checks                 │
│   - GUI “Validate Installation”                │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 5. Failure Handling                            │
│   - NSSM restarts process                      │
│   - Orchestrator logs error                    │
│   - GUI displays failure                       │
│   - Deployment rollback (if enabled)           │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ 6. Teardown / Uninstall                        │
│   - Invoke-ForensicUninstall                   │
│   - Stop services                              │
│   - Remove NSSM entries                        │
│   - Delete suite directories                   │
└──────────────────────────────────────────────┘
🟦 3. Cluster Orchestration Diagram
Control host → multiple nodes → Blue/Green → Runtime prep → Status report
Code
┌──────────────────────────────────────────────────────────────┐
│                    CONTROL HOST (Your Laptop)                 │
│   Invoke-ForensicRelease -Hosts 172,173,174                   │
│   ForensicSuite.Validation.psm1                               │
│   SSH + SCP                                                   │
└───────────────┬──────────────────────────────────────────────┘
                │
                │ Deploy to each host
                ▼
┌──────────────────────────────────────────────────────────────┐
│                    CLUSTER NODES (e.g., .172)                 │
│   Step 1: Deploy payload to inactive slot                     │
│   Step 2: Validate payload                                    │
│   Step 3: Switch symlink                                      │
│   Step 4: Install services                                    │
│   Step 5: Validate services                                   │
└───────────────┬──────────────────────────────────────────────┘
                │
                │ Parallel fan‑out (per host)
                ▼
┌──────────────────────────────────────────────────────────────┐
│                    RUNTIME PREPARATION                        │
│   - pip install requirements                                   │
│   - pip install wheel                                          │
│   - pip install .                                              │
│   - Validate imports                                           │
│   - install_services.ps1                                       │
└───────────────┬──────────────────────────────────────────────┘
                │
                │ After all hosts succeed
                ▼
┌──────────────────────────────────────────────────────────────┐
│                    FINAL CLUSTER STATUS                       │
│   Get-StatusReport                                             │
│   - Service states                                             │
│   - Slot states                                                │
│   - Symlink targets                                            │
│   - Runtime health                                             │
└──────────────────────────────────────────────────────────────┘

A complete, deterministic mental model of the entire deployment ecosystem — from source to cluster runtime.

1. GUI architecture diagram

┌──────────────────────────────────────────────┐
│                Forensic Suite v2 GUI         │
│            (forensic_suite_v2.gui.app)       │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ Qt Application Layer                         │
│  - QApplication                               │
│  - MainWindow (Cockpit)                      │
│  - TracerConsole (QDialog)                   │
│  - Menus, buttons, status bar                │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ Engine / Plugin Layer                        │
│  - Engine                                    │
│    - loads plugins via discover_plugins()    │
│    - exposes trace(chain, target)            │
│  - Plugins per chain (BTC/ETH/TRON/…)        │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ Script / Runtime Integration                 │
│  - Launch dashboards (PowerShell scripts)    │
│  - Launch indexers (run_*_indexer.ps1)       │
│  - Validate installation (files, plugins)    │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ External System Dependencies                 │
│  - Python runtime                            │
│  - Services (btc_indexer, eth_indexer, …)    │
│  - Logs (C:\forensic_suite_logs)             │
└──────────────────────────────────────────────┘

2. Service dependency graph

                          ┌───────────────────────┐
                          │  forensic_orchestrator│
                          │  (core coordinator)   │
                          └─────────┬─────────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          ▼                         ▼                         ▼
┌──────────────────┐     ┌──────────────────┐       ┌──────────────────┐
│  btc_indexer      │     │  eth_indexer      │       │  tron_indexer     │
│  (BTC chain)      │     │  (ETH chain)      │       │  (TRON chain)     │
└─────────┬────────┘     └─────────┬────────┘       └─────────┬────────┘
          │                        │                           │
          ▼                        ▼                           ▼
┌──────────────────┐     ┌──────────────────┐       ┌──────────────────┐
│  BTC node / APIs  │     │  ETH node / APIs  │       │  TRON node / APIs │
└──────────────────┘     └──────────────────┘       └──────────────────┘

All services depend on:
- Python 3.14 runtime
- forensic_suite_v2 package
- Shared config (env.json, YAML)
- C:\forensic_state\* and C:\forensic_suite_logs

3. Remote host filesystem layout diagram

C:\
├── forensic_suite_v2_blue\
│   ├── forensic_suite_v2\        (package tree)
│   ├── scripts\                  (Invoke-ForensicRelease, install_services, …)
│   ├── wheel\                    (forensic_suite_v2-*.whl)
│   ├── requirements.txt
│   └── bootstrap.ps1
├── forensic_suite_v2_green\
│   ├── (same structure as blue)
│   └── …
├── forensic_suite_v2  (symlink → blue or green)
│   ├── forensic_suite_v2\
│   ├── scripts\
│   ├── wheel\
│   └── requirements.txt
├── forensic_state\
│   ├── btc\
│   ├── eth\
│   └── tron\
├── forensic_suite_logs\
│   ├── btc_indexer.log
│   ├── eth_indexer.log
│   ├── tron_indexer.log
│   └── forensic_orchestrator.log
├── forensic_secrets\
│   └── env.json
└── tools\
    └── nssm\nssm.exe
	└── handle\handle.exe

4. Python environment isolation diagram

┌──────────────────────────────────────────────┐
│ System Python (if any)                       │
│  - C:\Users\...\AppData\...                  │
│  - WindowsApps\python.exe (ignored)          │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│ Dedicated Forensic Python                    │
│  - C:\Program Files\Python314\python.exe     │
│  - Used by:                                  │
│      - Runtime prep                          │
│      - Services (NSSM)                       │
│      - GUI / CLI                             │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ Environment Contents (Python314)             │
│  - pip, setuptools, wheel                    │
│  - forensic_suite_v2 (from wheel + pip .)    │
│  - Core deps: orjson, PyYAML, requests, …    │
│  - GUI deps: PySide6, qt_material, qasync,   │
│              pyqtgraph, pillow               │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│ Isolation Guarantees                         │
│  - Services always use Python314             │
│  - No reliance on user PATH                  │
│  - No interference from WindowsApps shim     │
│  - Deterministic imports & versions          │
└──────────────────────────────────────────────┘
