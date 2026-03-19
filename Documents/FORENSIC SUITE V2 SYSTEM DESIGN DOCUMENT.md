FORENSIC SUITE V2 SYSTEM DESIGN DOCUMENT (.md)

Date: 2026-03-15
Status: Verified on host 192.168.0.172

---

1. PURPOSE

---

This document describes the operational architecture of the
Forensic Suite V2 deployment system and runtime services.

The platform performs blockchain indexing across multiple
chains (BTC, ETH, TRON) and stores forensic data in a
central PostgreSQL database.

The system supports controlled cluster deployment using a
blue/green release model and Windows services managed via NSSM.

---

2. BUILD AND RELEASE WORKFLOW

---

Development occurs on the primary workstation.

Source repository:

F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root

Typical release workflow:

1. syncdev
   Synchronises working source files.

2. Update-InstallerPayload
   Prepares the payload that will be deployed to hosts.

3. Invoke-ForensicRelease -BuildOnly
   Produces the deployable wheel/payload.

4. Invoke-ForensicRelease -DeployOnly
   Deploys the payload to cluster hosts.

The deployment process copies the payload to the target host
and activates it using the blue/green slot mechanism.

---

3. DEPLOYMENT TARGETS

---

Current cluster nodes:

192.168.0.199
192.168.0.28  (PostgreSQL host)
192.168.0.172  (validated proof host)
192.168.0.165

Each host receives the same application payload.

---

4. BLUE/GREEN SLOT MODEL

---

Active application path:

C:\forensic_suite_v2

This path is a symbolic link that points to the currently
active deployment slot.

Example:

C:\forensic_suite_v2 -> C:\forensic_suite_v2_green

The deployment process installs into a slot directory
(e.g. forensic_suite_v2_green) and then updates the symlink.

Advantages:

• Zero-downtime switching
• Safe rollback capability
• Clean separation between builds

---

5. APPLICATION DIRECTORY STRUCTURE

---

C:\forensic_suite_v2_green

Key directories:

forensic_suite_v2
config
indexer.yaml

```
core\
    orchestrator.py
    indexer_engine.py

btc_indexer\
eth_indexer\
tron_indexer\

scripts\
    install_services.ps1
```

External runtime directories:

C:\forensic_suite_logs
C:\forensic_state

---

6. WINDOWS SERVICE MODEL

---

Services are installed using NSSM:

F:\tools\nssm\nssm.exe

Four Windows services are created:

btc_indexer
eth_indexer
tron_indexer
forensic_orchestrator

The services run the Python indexer components and
the orchestration supervisor.

---

7. ORCHESTRATOR DESIGN

---

File:

forensic_suite_v2\core\orchestrator.py

Responsibilities:

• Load indexer.yaml configuration
• Determine which chains should run
• Create service instances for each chain
• Launch supervised async tasks
• Monitor services using a watchdog loop
• Restart chains if a crash occurs

The orchestrator reads:

config/indexer.yaml

Example configuration section:

chains:

* tron
* eth
* btc

---

8. INDEXER SERVICES

---

Each blockchain indexer runs as an async service built
on the shared BaseIndexerService.

Indexers:

BtcIndexerService
EthIndexerService
TronIndexerService

Each indexer performs:

• block scanning
• transaction extraction
• database writes
• checkpoint management
• reorganisation detection

---

9. CHECKPOINT SYSTEM

---

Checkpoint files store the last indexed block height.

They are intentionally stored outside the deploy directory
so deployments do not erase runtime state.

Checkpoint location:

C:\forensic_state

Files:

btc_checkpoint.json
eth_checkpoint.json
tron_checkpoint.json

Example structure:

{
"last_block": 47106
}

---

10. LOGGING

---

All services use structured JSON logging.

Log directory:

C:\forensic_suite_logs

Typical files:

btc_indexer.err.log
btc_indexer.out.log

eth_indexer.err.log
eth_indexer.out.log

tron_indexer.err.log
tron_indexer.out.log

forensic_orchestrator.err.log
forensic_orchestrator.out.log

Logs are useful for:

• service diagnostics
• restart analysis
• performance monitoring

---

11. DATABASE

---

All indexers write to a central PostgreSQL database.

Database host:

192.168.0.28

Connection parameters are defined in:

config/indexer.yaml

---

12. VALIDATED HOST STATE (.172)

---

Host:

192.168.0.172

Verified status:

btc_indexer            RUNNING
eth_indexer            RUNNING
tron_indexer           RUNNING
forensic_orchestrator  RUNNING

Orchestrator log confirms:

chains:
tron
eth
btc

All three chain services successfully started.

---

13. OPERATIONAL NOTES

---

Key operational principles:

• Checkpoints must remain outside the deploy directory
• Deployment slots must not contain runtime state
• Services should be restarted via install_services.ps1
• Structured logs are the primary diagnostic tool

---

## END OF DOCUMENT
