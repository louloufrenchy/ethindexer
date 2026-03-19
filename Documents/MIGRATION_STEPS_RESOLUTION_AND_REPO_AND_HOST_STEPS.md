# Forensic Suite v2 Migration — Full Operational Summary  
**Author:** Louis  
**System:** WIN‑U0AR3HQSOJB  
**Date:** 2026‑02‑19  
**Status:** ✅ All indexers validated and running

---

# 1. Database Port + Central Host Fixing

### Problem
Indexers were reading configs from **local host configs** instead of the **central unified DB host**, causing:
- mismatched DB ports  
- indexers writing to different databases  
- schema drift  
- ingestion failures  

### Fix
All indexer YAML configs were updated so that:

postgres:
    host: 192.168.0.28
    port: 5432
    user: postgres
    password: Str0ngPassw0rd2025
    database: forensic


This ensured:
- all chains write to the **same unified forensic DB**
- validator reads the correct schema
- ingestion is centralized and deterministic

---

# 2. Full SQL Migration Log (BTC → TRON → ETH → Metrics)

Below is the **exact sequence** of SQL operations executed to migrate the legacy v1 schema into the fully aligned v2 schema.

---

## 2.1 BTC Migration (Flatten + Type Fixes)

### `btc_blocks`
- Converted timestamptz → timestamp
- Ensured PK on block_number

### `btc_transactions`
- Flattened partitions
- Converted timestamptz → timestamp
- Ensured PK on tx_hash

---

## 2.2 TRON Migration

### `tron_blocks`
```sql
DROP TABLE IF EXISTS public.tron_blocks CASCADE;
ALTER TABLE public.tron_block_hashes RENAME TO tron_blocks;
ALTER TABLE public.tron_blocks DROP CONSTRAINT IF EXISTS tron_block_hashes_pkey;
ALTER TABLE public.tron_blocks ADD COLUMN IF NOT EXISTS ts timestamp without time zone;
UPDATE public.tron_blocks SET ts = to_timestamp(0) WHERE ts IS NULL;
ALTER TABLE public.tron_blocks ADD CONSTRAINT tron_blocks_pkey PRIMARY KEY (block_number);

tron_transactions (flatten + hashing)

CREATE TABLE public.tron_transactions_v2 (
  tx_hash text PRIMARY KEY,
  block_number bigint NOT NULL,
  ts timestamp without time zone NOT NULL,
  status text
);

INSERT INTO public.tron_transactions_v2 (...)
SELECT
  encode(digest(txid || block_number || extract(epoch FROM ts) || coalesce(status,''), 'sha256'),'hex'),
  block_number,
  ts AT TIME ZONE 'UTC',
  status
FROM public.tron_transactions;

DROP TABLE public.tron_transactions CASCADE;
ALTER TABLE public.tron_transactions_v2 RENAME TO tron_transactions;

2.3 ETH Migration
eth_blocks
Already v2‑aligned — no changes required.

eth_transactions

CREATE TABLE public.eth_transactions_v2 (
  tx_hash text PRIMARY KEY,
  block_number bigint NOT NULL,
  ts timestamp without time zone NOT NULL,
  status integer
);

INSERT INTO public.eth_transactions_v2 (...)
SELECT
  tx_hash,
  block_number,
  ts AT TIME ZONE 'UTC',
  CASE WHEN status ~ '^[0-9]+$' THEN status::integer ELSE NULL END
FROM public.eth_transactions;

DROP TABLE public.eth_transactions CASCADE;
ALTER TABLE public.eth_transactions_v2 RENAME TO eth_transactions;

2.4 indexer_metrics Migration

CREATE TABLE public.indexer_metrics_v2 (
  ts timestamp without time zone NOT NULL,
  chain text NOT NULL,
  last_block bigint NOT NULL,
  chain_head bigint NOT NULL,
  lag bigint NOT NULL,
  mode text,
  db_queue_depth bigint
);

INSERT INTO public.indexer_metrics_v2 (...)
SELECT
  ts AT TIME ZONE 'UTC',
  chain,
  last_block,
  chain_head,
  lag,
  mode,
  db_queue_depth
FROM public.indexer_metrics;

DROP TABLE public.indexer_metrics CASCADE;
ALTER TABLE public.indexer_metrics_v2 RENAME TO indexer_metrics;

3. Indexer Code Fix (Python Path Injection)
All indexers were updated to ensure they correctly import the monorepo root:

import sys, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

This fixed:

module resolution failures

incorrect relative imports

broken service entrypoints

4. Installer Payload Drift
Problem
The installer payload (service installers, scripts, configs) was outdated relative to the live system.

Required Action
The payload must be regenerated from the current monorepo state, including:

updated indexer code

updated config templates

updated service installers

updated bootstrap scripts

updated uninstall scripts

updated environment variable injection

updated schema expectations

This ensures:

future upgrades do not regress

blue/green deployments remain deterministic

no drift between payload and production

5. Proper Command to Start Indexers
The canonical command:

& cmd.exe /c 'set PYTHONPATH=C:\forensic_suite_v2_green && "C:\Program Files\Python314\python.exe" "C:\forensic_suite_v2_green\forensic_suite_v2\btc_indexer\services\run_btc_indexer_v2.py"'

This:

injects PYTHONPATH

runs the v2 validator

starts ingestion only if schema is correct

This is the only correct entrypoint for BTC, ETH, TRON indexers in v2.

6. Additional Notes / Hidden Fixes
✔ Partition flattening
All partitioned tables (BTC, TRON, ETH) were flattened to meet v2 validator requirements.

✔ Timestamp normalization
All timestamptz → timestamp conversions were completed.

✔ Primary key alignment
All PKs now match v2 expectations.

✔ Hashing for TRON
TRON v1 txid was not globally unique → deterministic SHA‑256 hashing was introduced.

✔ Metrics cleanup
indexer_metrics was normalized and cleaned.

✔ Unified DB
All indexers now write to the same forensic database.

✔ Validator green
All tables now pass the v2 schema validator.

Final Status
🎉 Schema validation passed. Safe to start indexers.  
All chains are ingesting.
The system is now fully v2‑aligned, deterministic, and ready for:

ingestion correctness validation

dashboard rebuild

archival checkpoints

blue/green orchestration

MAIN REPO A UPDATES NEEDED FOR OTHER HOSTS

# Repo A, Installer Payload, and Host Sync — Operational Plan

## 1. Make Repo A the single source of truth

**Goal:** Repo A must exactly reflect what is now running on `WIN-U0AR3HQSOJB`.

### 1.1. Sync code and layout from the live green tree

From `WIN-U0AR3HQSOJB`:

- **Compare and sync**:

  - `C:\forensic_suite_v2_green\forensic_suite_v2\btc_indexer\`
  - `C:\forensic_suite_v2_green\forensic_suite_v2\tron_indexer\`
  - `C:\forensic_suite_v2_green\forensic_suite_v2\eth_indexer\`
  - `C:\forensic_suite_v2_green\forensic_suite_v2\scripts\`
  - Any shared libs used by indexers

Into the corresponding paths in **Repo A** (the monorepo), so that:

- The Python path injection block:

  ```python
  import sys, os

  ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
  if ROOT not in sys.path:
      sys.path.insert(0, ROOT)

is present in all indexer entrypoints and services.

The validator‑passing code is what lives in Repo A, not just on the host.

1.2. Sync configuration templates
In Repo A, ensure:

The config templates (YAML/JSON) for BTC/TRON/ETH indexers point to the central DB host and port.

Any env.json or .env templates match what is actually used on WIN-U0AR3HQSOJB.

Repo A must be able to regenerate C:\forensic_suite_v2_green from scratch.

2. Requirements and Python environment
Goal: requirements are explicit and part of the payload workflow so all 3 other hosts converge.

2.1. Capture the real environment into requirements.txt
On WIN-U0AR3HQSOJB (inside the v2 environment):

"c:\Program Files\Python314\python.exe" -m pip freeze > C:\forensic_suite_v2_green\requirements.txt

Then:

Copy requirements.txt into Repo A at a canonical location, e.g.:

repo_root/infra/requirements/forensic_suite_v2_requirements.txt

or repo_root/forensic_suite_v2/requirements.txt

PS C:\development\scripts>
PS C:\development\scripts> scp -i C:\Users\louis\.ssh\id_ed25519 F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\requirements.txt forensicuser@192.168.0.28:C:\forensic_suite_v2_green\requirements.txt
requirements.txt                                                                                                          100%  677   110.2KB/s   00:00
PS C:\development\scripts> scp -i C:\Users\louis\.ssh\id_ed25519 F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\requirements.txt forensicuser@192.168.0.172:C:\forensic_suite_v2_green\requirements.txt
requirements.txt                                                                                                          100%  677   165.3KB/s   00:00
PS C:\development\scripts> scp -i C:\Users\louis\.ssh\id_ed25519 F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\requirements.txt forensicuser@192.168.0.165:C:\forensic_suite_v2_green\requirements.txt
requirements.txt                                                                                                          100%  677    66.1KB/s   00:00
PS C:\development\scripts> scp -i C:\Users\louis\.ssh\id_ed25519 F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\requirements.txt forensicuser@192.168.0.199:C:\forensic_suite_v2_green\requirements.txt
requirements.txt                                                                                                          100%  677   110.2KB/s   00:00
PS C:\development\scripts> hostname
LAPTOP-229C74PJ
PS C:\development\scripts>

2.2. Define the installer behavior for requirements
In Repo A, document and script:

Installer step:

"c:\Program Files\Python314\python.exe" -m pip install -r requirements.txt

This must be part of the payload install/upgrade workflow, not a manual step.

So the payload will always:

Lay down the code tree.

Install/upgrade Python packages from requirements.txt.

Register/update services.

Run the validator before starting indexers.

3. Rebuild the installer payload from Repo A
Goal: the payload is generated from Repo A, not from a live host.

3.1. Define payload contents in Repo A
In Repo A, define a payload manifest (even if just documented):

Include:

forensic_suite_v2/ (indexers, libs, scripts)

requirements.txt

Service install scripts (PowerShell / batch)

Config templates (YAML/JSON)

Any bootstrap/uninstall scripts

A small RUN_VALIDATOR_AND_START.ps1 wrapper

3.2. Build payload artifact
From Repo A CI or a local build step:

Package into a versioned artifact, e.g.:

forensic_suite_v2_payload_v9.3.3.zip

or forensic_suite_v2_payload_2026-02-19.zip

This artifact is now the only thing deployed to the 3 other hosts.

4. Sync to the other 3 hosts
Goal: all hosts converge to the same state as WIN-U0AR3HQSOJB.

4.1. Deployment steps per host
On each of the 3 hosts:

Stop existing services (btc/tron/eth indexers).

Backup old tree (e.g. C:\forensic_suite_v2_legacy_YYYYMMDD).

Extract payload to C:\forensic_suite_v2_green.

Run:

"c:\Program Files\Python314\python.exe" -m pip install -r C:\forensic_suite_v2_green\requirements.txt

Run the service installer script from the payload (from Repo A).

Run the validator+start command:

& cmd.exe /c 'set PYTHONPATH=C:\forensic_suite_v2_green && "C:\Program Files\Python314\python.exe" "C:\forensic_suite_v2_green\forensic_suite_v2\btc_indexer\services\run_btc_indexer_v2.py"'

Confirm schema validation passes and ingestion starts.

5. Sync strategy (Repo A ↔ Hosts)
You’re right: a sync is needed in both directions:

Now: host → Repo A (to capture the working state).

From now on: Repo A → hosts (via payload).

5.1. One‑time back‑sync (what we just did conceptually)
Copy working code and configs from WIN-U0AR3HQSOJB into Repo A.

Commit with a clear message, e.g.:

feat: align forensic_suite_v2 with production v2 schema and indexer fixes

5.2. Forward sync via payload
All future changes are made in Repo A.

CI builds a new payload.

Payload is deployed to all hosts.

No more ad‑hoc edits on hosts.

6. Checklist to confirm everything is “correct”
Repo A:

[ ] Contains the updated indexer code with Python path injection.

[ ] Contains the correct config templates pointing to the central DB.

[ ] Contains requirements.txt captured from the working host.

[ ] Contains installer/uninstaller scripts and service definitions.

[ ] Has a documented payload build process.

Payload:

[ ] Includes forensic_suite_v2 tree.

[ ] Includes requirements.txt.

[ ] Includes service install scripts.

[ ] Includes a validator+start wrapper.

Hosts (all 4):

[ ] Use the same payload version.

[ ] Use the same requirements.txt.

[ ] Use the same DB host/port.

[ ] Pass the schema validator before starting indexers.

7. What you implicitly fixed (and must preserve in Repo A)
Correct DB routing to the central host.

v2‑aligned schemas for BTC/TRON/ETH/metrics.

Deterministic TRON tx hashing.

Flattened partitions.

Timestamp normalization.

Python path injection.

Validator‑gated startup.

All of that now needs to be baked into Repo A and the payload, so the other 3 hosts don’t drift and future upgrades are safe.
