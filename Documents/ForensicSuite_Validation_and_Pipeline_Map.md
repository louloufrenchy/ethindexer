================================================================================
FORENSIC SUITE V9.3.3 — MODULE‑WIDE VALIDATION MAP
Relaxed Repo A (Development Workspace) + Strict Repo B (Runtime‑Only Mirror)
================================================================================

This map shows every command in the module, which validators it calls, and in what
order. It reflects the fully updated V9.3.3 architecture:

    • Repo A  = full development workspace (allowed to contain anything)
    • Repo B  = strict runtime‑only wheel mirror
    • Combined Validator = single source of truth for validation
    • Preflight = universal gatekeeper
    • Repair‑Workspace = deterministic recovery path

================================================================================
1. Test‑ForensicSuiteAll
================================================================================
Purpose:
    Direct validation entrypoint.

Calls:
    scripts\forensic_suite_Combined_validator.ps1

Flow:
    Test‑ForensicSuiteAll
        → Combined Validator
            → Validate Repo A (relaxed)
            → Validate Repo B (strict)

Exit Codes:
    0  = clean
    1  = Repo A missing required anchors
    2  = Repo B invalid
    99 = validator missing

================================================================================
2. Invoke‑Preflight
================================================================================
Purpose:
    Gatekeeper for Sync‑Dev, Build‑Suite, Deploy‑Suite.

Calls:
    scripts\Invoke-Preflight.ps1
        → forensic_suite_Combined_validator.ps1

Flow:
    Invoke‑Preflight
        → Combined Validator
            → Validate Repo A (relaxed)
            → Validate Repo B (strict)

Exit Codes:
    Same as Combined Validator.

================================================================================
3. Clear‑ForensicSuiteAll
================================================================================
Purpose:
    Reset Repo B before Sync‑Dev or Build‑Suite.

Calls:
    scripts\forensic_suite_RepoB_cleanup.ps1

Flow:
    Clear‑ForensicSuiteAll
        → RepoB Cleanup Script
            → Delete all contents of Repo B
            → Recreate runtime‑only structure

Validation:
    None (cleanup only).

================================================================================
4. Repair‑Workspace
================================================================================
Purpose:
    Deterministic recovery path.

Calls:
    forensic_suite_RepoB_cleanup.ps1
    Invoke‑Preflight.ps1
    Sync‑DevTrees.FullSuite.ps1 -ForceApply

Flow:
    Repair‑Workspace
        → Clear Repo B
        → Invoke‑Preflight
            → Combined Validator
        → Sync‑Dev Apply

Guarantees:
    Repo B always rebuilt cleanly.
    Repo A never touched.
    No partial state.

================================================================================
5. Update‑ForensicSuiteDev
================================================================================
Purpose:
    Sync‑Dev DryRun or Apply.

Calls:
    Sync‑DevTrees.FullSuite.ps1
        → Invoke‑Preflight
        → Sync‑DevTrees.DryRun.ps1
        → Sync‑DevTrees.Apply.ps1
        → Sync‑DevTrees.Validate.ps1

Flow:
    Update‑ForensicSuiteDev
        → FullSuite.ps1
            → Invoke‑Preflight
                → Combined Validator
            → DryRun
            → Apply
            → RepoB Validation (runtime‑only)

Validation:
    Preflight (Repo A + Repo B)
    Post‑Apply Repo B validation.

================================================================================
6. Invoke‑BuildSuiteSafe
================================================================================
Purpose:
    Deterministic build with enforced cleanup.

Calls:
    Clear‑ForensicSuiteAll
    Invoke‑BuildSuite

Flow:
    Invoke‑BuildSuiteSafe
        → Clear Repo B
        → Invoke‑BuildSuite
            → Invoke‑Preflight
                → Combined Validator
            → Build wheel + PyInstaller
            → Refresh installer payload
            → Build installer EXE
            → Post‑install validation
            → Payload integrity validation

Validation:
    Preflight (Repo A + Repo B)
    Installer payload validation
    Post‑install validation

================================================================================
7. Invoke‑BuildSuite
================================================================================
Purpose:
    Full build without forced cleanup.

Calls:
    Invoke‑Preflight
    Build scripts
    Payload validation scripts

Flow:
    Invoke‑BuildSuite
        → Invoke‑Preflight
            → Combined Validator
        → Build wheel
        → Build PyInstaller bundle
        → Refresh installer payload
        → Build installer EXE
        → Post‑install validation
        → Payload integrity validation

Validation:
    Same as BuildSuiteSafe, minus cleanup.

================================================================================
8. Invoke‑DeployPreflight
================================================================================
Purpose:
    Validate installer payload + EXE before deployment.

Calls:
    validate_installer_payload.ps1
    Checks for installer EXE
    Checks for deployment scripts

Flow:
    Invoke‑DeployPreflight
        → Payload integrity validation
        → Installer EXE existence
        → Deployment script existence

Validation:
    Does NOT validate Repo A or Repo B.

================================================================================
9. Invoke‑DeployHost / Invoke‑DeployCluster
================================================================================
Purpose:
    Deployment to nodes.

Calls:
    Invoke‑DeployPreflight
    Deployment scripts

Flow:
    Invoke‑DeployHost / Invoke‑DeployCluster
        → Invoke‑DeployPreflight
            → Payload integrity validation
            → Installer EXE validation
            → Deployment script validation
        → Deployment

Validation:
    Only payload + installer EXE.

================================================================================
SUMMARY TABLE
================================================================================
Command                     Repo A?     Repo B?     Payload?     Installer EXE?
--------------------------------------------------------------------------------
Test‑ForensicSuiteAll       ✔ relaxed   ✔ strict    ✖            ✖
Invoke‑Preflight            ✔ relaxed   ✔ strict    ✖            ✖
Clear‑ForensicSuiteAll      ✖           ✖           ✖            ✖
Repair‑Workspace            ✔ via PF    ✔ via PF    ✖            ✖
Update‑ForensicSuiteDev     ✔ via PF    ✔ via PF    ✖            ✖
Invoke‑BuildSuiteSafe       ✔ via PF    ✔ via PF    ✔            ✔
Invoke‑BuildSuite           ✔ via PF    ✔ via PF    ✔            ✔
Invoke‑DeployPreflight      ✖           ✖           ✔            ✔
Invoke‑DeployHost/Cluster   ✖           ✖           ✔            ✔

================================================================================
END OF MAP
================================================================================
