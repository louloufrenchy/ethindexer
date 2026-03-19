FOR FORENSIC SUITE V2 — CHANGE SUMMARY
Date: 2026-03-14
Environment: Source host + cluster deployment workflow
Purpose: Record the current stable state before future changes move to a proper git checkout workflow.

======================================================================
1. IMPORTANT WORKING RULE GOING FORWARD
======================================================================

The codebase was updated directly in-place without first creating a git checkout / clean feature branch.
That was acceptable for recovery and stabilization, but it should stop here.

From this point forward:

- treat the current code as the new stable baseline
- commit or tag the current stable state
- do future changes only from a fresh checkout / branch
- avoid direct live edits on destination hosts except emergency diagnostics
- if a destination host is edited for troubleshooting, back-sync once into Repo A, then stop editing hosts directly

Recommended next git discipline:

1. git status
2. review all modified files
3. commit current stable baseline
4. create a new branch for future work
5. all future updates flow:
   Repo A -> Sync-Dev -> build -> test_install -> deploy

======================================================================
2. MAIN OUTCOME
======================================================================

The suite is now in a materially better state:

- Sync-Dev now completes successfully end-to-end
- Repo B cleanup / pre-sync / apply / validation path is working
- local test install on source host succeeded far enough to prove:
  - payload staging works
  - requirements install works
  - wheel install works
  - NSSM-based service installation works
  - all services can run
- the Unicode crash in schema validation was identified and fixed
- the old false build abort message was identified as wrapper/output-handling noise, not a real build failure
- the deployment pipeline is ready for deployment to all hosts

Logs proved:
- Sync-Dev full suite completed successfully
- BuildSuite completed successfully even when a false [ABORT] line appeared in the wrapper output
- test install showed services running
- package artifacts were built successfully
- installer payload validation passed
- wheel + installer build succeeded
- source-host service state reached Running for all services in the final status check 

======================================================================
3. MAJOR ISSUES IDENTIFIED AND RESOLVED
======================================================================

A. SSH / host connectivity issues
- host IP changes and SSH trust issues were resolved
- password prompt issue on 192.168.0.28 was resolved
- SSH key / permissions / host key state were stabilized

B. Profile / workspace loading
- loadfs alias / workspace loading issues were corrected
- ForensicSuite.Validation module import and alias behavior was stabilized

C. Build wrapper false failure
- build logs showed a false [ABORT] message in the middle of a successful build
- root cause: wrapper logic was treating build output text as a failure indicator
- actual build continued and completed successfully
- confirmed by final payload validation and completed build suite output :contentReference[oaicite:1]{index=1}

D. Repo B validation / Sync-Dev ordering
- Repo B validator originally failed on partial or empty states
- Sync-Dev was validating Repo B too early
- cleanup + pre-sync validation + apply + post-sync validation flow was redesigned
- Sync-Dev now completes successfully end-to-end

E. test_install vs Repo B shared folder problem
- service-created runtime residue in shared folders created validation noise
- Repo B cleanup / pre-sync validation logic was hardened

F. install_services.ps1 issues
- multiple parser / quoting issues were resolved
- direct raw service registration of .py / .ps1 entry points was not reliable
- switched to NSSM-based service installation model for test install
- services are now able to run under the Windows Service Control Manager

G. schema validator Windows Unicode crash
- services crashed because schema_validator.py printed Unicode symbols like ✅
- Windows service stdout under cp1252 could not encode those characters
- fixed by replacing Unicode/emoji-style output with ASCII-safe output and safe printing logic
- this removed the repeated restart/crash pattern seen in ETH/TRON logs :contentReference[oaicite:2]{index=2}

H. secrets/status alignment
- suite logic was aligned toward F:\forensic_secrets\env.json
- status logic was reviewed and improved to use that path rather than expecting env.json inside Repo A

I. Python / requirements / build environment
- Python 3.14 became the target runtime baseline
- requirements installation was brought into the deployment/test flow
- build tools for Python 3.14 were installed so wheel build could succeed
- NSSM was added/ensured for service wrapping

======================================================================
4. SCRIPTS / FILES MODIFIED OR REPLACED
======================================================================

These are the main files changed during the stabilization effort.

TOP-LEVEL / BUILD / DEPLOY
- build_final.ps1
- test_install.ps1
- installer_script.iss
- requirements.txt
- post_install_validation.ps1
- refresh_installer_payload.ps1

MODULE / ORCHESTRATION
- scripts\ForensicSuite.Validation.psm1
- scripts\Invoke-ForensicRelease.ps1
- scripts\Invoke-Preflight.ps1

SYNC-DEV / REPO VALIDATION / CLEANUP
- scripts\Sync-DevTrees.FullSuite.ps1
- scripts\Sync-DevTrees.Apply.ps1
- scripts\Sync-DevTrees.DryRun.ps1
- scripts\Sync-DevTrees.Validate.ps1
- scripts\Sync-DevTrees.Rollback.ps1
- scripts\forensic_suite_RepoA_validator_v2.ps1
- scripts\forensic_suite_RepoB_validator.ps1
- scripts\forensic_suite_RepoB_cleanup.ps1
- scripts\forensic_suite_Combined_validator.ps1
- scripts\forensic_suite_repo_mapping.ps1
- scripts\forensic_suite_rebuild_repo_csv.ps1

PAYLOAD / INSTALLER CONTENT
- installer_payload refresh logic
- payload structure for scripts / wheel / bootstrap / env template / requirements
- payload sync behavior for forensic_suite_v2 runtime tree

RUNTIME / SERVICE INSTALLATION
- forensic_suite_v2\scripts\install_services.ps1
- forensic_suite_v2\scripts\operator_console.ps1
- forensic_suite_v2\scripts\operator_console.py
- forensic_suite_v2\scripts\healthcheck.py
- forensic_suite_v2\scripts\healthcheck_core.py
- forensic_suite_v2\scripts\start_all_indexers.py
- forensic_suite_v2\scripts\db_migrate.py
- forensic_suite_v2\scripts\windows_orchestrator_service.ps1

INDEXER ENTRYPOINTS / SERVICE-RUNNER PATHS
- forensic_suite_v2\btc_indexer\services\run_btc_indexer_v2.py
- forensic_suite_v2\eth_indexer\services\run_eth_indexer_v2.py
- forensic_suite_v2\tron_indexer\services\run_tron_indexer_v2.py

INDEXER SERVICE CLASSES / RUNTIME SUPPORT
- forensic_suite_v2\btc_indexer\services\btc_indexer_service.py
- forensic_suite_v2\eth_indexer\services\eth_indexer_service.py
- forensic_suite_v2\tron_indexer\services\tron_indexer_service.py

CORE / VALIDATION
- forensic_suite_v2\core\schema_validator.py

CONFIG
- forensic_suite_v2\config\indexer.yaml
- forensic_suite_v2\btc_indexer\config\indexer.yaml
- forensic_suite_v2\eth_indexer\config\indexer.yaml
- forensic_suite_v2\tron_indexer\config\indexer.yaml

Possible additional related changes also occurred in:
- bootstrap.ps1
- env.template.json
- dot_env.template
- any referenced legacy backups / restore scripts
- payload-side copies of the scripts above

Reference repo state also showed wide script/payload changes and untracked additions in scripts/, installer_payload/, and legacy/ areas. :contentReference[oaicite:3]{index=3}

======================================================================
5. ARCHITECTURAL DECISIONS NOW IN EFFECT
======================================================================

1. Repo A is authoritative
- all meaningful code changes must live in Repo A
- Repo B is only the runtime mirror
- hosts should not become the source of truth

2. Repo B is runtime-only
- cleaned before sync
- validated pre-sync as empty/cleanable
- populated only by Sync-Dev apply
- validated again after apply

3. Secrets live outside Repo A
- canonical secrets path:
  F:\forensic_secrets\env.json

4. Python runtime standard
- Python 3.14 is the intended host baseline

5. Service hosting model
- service install/testing moved toward NSSM-based wrapping
- do not rely on raw .py / .ps1 commands as native Windows services without a wrapper

6. Validation/logging discipline
- no Unicode/emoji output from Windows services
- use ASCII-safe service logs and validator output

======================================================================
6. KNOWN STABLE WORKFLOW NOW
======================================================================

Recommended workflow from this point:

1. loadfs
2. syncdev
3. Invoke-ForensicRelease -BuildOnly
4. .\scripts\test_install.ps1
5. verify services
6. Invoke-ForensicRelease -DeployOnly
7. Get-StatusReport

Equivalent shorthand operational flow:

- sync Repo A to Repo B
- build artifacts
- run local source-host mirror install test
- confirm all services run
- deploy to cluster
- check cluster status

======================================================================
7. VERIFIED/PROVEN STATES
======================================================================

A. Sync-Dev
The Sync-Dev full suite now completes successfully:
- Repo A validate
- Repo B cleanup
- Repo B pre-sync validate
- dry-run
- apply
- post-sync validate

B. Build
Build suite reached successful payload validation and completed successfully, despite the false wrapper [ABORT] line appearing in the logs. :contentReference[oaicite:4]{index=4}

C. Test install
The source-host test install reached the point where services were installed and service status could be verified. Final service logs later showed all four services Running:
- btc_indexer
- eth_indexer
- tron_indexer
- forensic_orchestrator :contentReference[oaicite:5]{index=5}

======================================================================
8. REMAINING CAUTIONS BEFORE / AFTER CLUSTER DEPLOY
======================================================================

1. The current code should now be treated as stable baseline.
2. Before any more edits, create a git commit / branch.
3. After cluster deploy, immediately run:
   - Get-StatusReport
   - targeted service checks on all hosts
   - payload/version checks if needed
4. Keep an eye on:
   - ETH/TRON runtime logs
   - schema validation output
   - any host with differing Python state
   - any host where NSSM or Python 3.14 is not aligned

======================================================================
9. RECOMMENDED NEXT ACTIONS
======================================================================

1. Commit/tag the current stable code.
2. Run deployment to all hosts.
3. Run cluster verification checks.
4. Only after stability is confirmed, begin any further improvements from a fresh checkout/branch.

Suggested git discipline after deployment:
- git status
- git add reviewed files
- git commit -m "Stabilize V9.3.5 build/sync/test/deploy pipeline"
- git checkout -b next-change-branch

======================================================================
10. SHORT OPERATOR NOTE
======================================================================

The current suite is stable enough to proceed with deployment.
The biggest lesson from this cycle is:

- direct in-place edits were useful for recovery
- but future work must move to a proper checkout / branch workflow
- Repo A must remain authoritative
- test install must remain the gate before cluster deployment

END OF SUMMARY
