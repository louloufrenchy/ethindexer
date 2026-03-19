flowchart TD

    %% ============================
    %% SECTION: VALIDATORS
    %% ============================

    subgraph VALIDATORS[Validators]
        A1[Combined Validator<br/>• Repo A (relaxed)<br/>• Repo B (strict)]
    end

    %% ============================
    %% SECTION: CLEANUP
    %% ============================

    subgraph CLEANUP[Cleanup]
        C1[Clear‑ForensicSuiteAll<br/>→ RepoB Cleanup Script<br/>→ Recreate runtime‑only structure]
    end

    %% ============================
    %% SECTION: PREFLIGHT
    %% ============================

    subgraph PREFLIGHT[Preflight]
        P1[Invoke‑Preflight.ps1<br/>→ Calls Combined Validator]
    end

    %% ============================
    %% SECTION: SYNC‑DEV
    %% ============================

    subgraph SYNCDEV[Sync‑Dev Pipeline]
        SD1[Sync‑DevTrees.FullSuite.ps1]
        SD2[DryRun]
        SD3[Apply<br/>→ Rebuild Repo B]
        SD4[Post‑Apply RepoB Validation]
    end

    %% ============================
    %% SECTION: BUILD SUITE
    %% ============================

    subgraph BUILDSUITE[Build Suite]
        BS1[Invoke‑BuildSuiteSafe]
        BS2[Invoke‑BuildSuite]
        BS3[Build Wheel]
        BS4[Build PyInstaller Bundle]
        BS5[Refresh Installer Payload]
        BS6[Build Installer EXE]
        BS7[Post‑Install Validation]
        BS8[Payload Integrity Validation]
    end

    %% ============================
    %% SECTION: DEPLOY
    %% ============================

    subgraph DEPLOY[Deployment]
        D1[Invoke‑DeployPreflight<br/>→ Payload Integrity<br/>→ Installer EXE Exists<br/>→ Deployment Scripts Exist]
        D2[Invoke‑DeployHost]
        D3[Invoke‑DeployCluster]
    end

    %% ============================
    %% SECTION: REPAIR WORKSPACE
    %% ============================

    subgraph REPAIR[Repair‑Workspace]
        R1[Repair‑Workspace.ps1<br/>→ Clear Repo B<br/>→ Preflight<br/>→ Sync‑Dev Apply]
    end

    %% ============================
    %% SECTION: ENTRYPOINTS
    %% ============================

    subgraph ENTRYPOINTS[User Commands]
        E1[Test‑ForensicSuiteAll]
        E2[Update‑ForensicSuiteDev]
        E3[Invoke‑BuildSuiteSafe]
        E4[Invoke‑BuildSuite]
        E5[Repair‑Workspace]
        E6[Invoke‑DeployHost]
        E7[Invoke‑DeployCluster]
    end

    %% ============================
    %% CONNECTIONS
    %% ============================

    %% Test‑ForensicSuiteAll
    E1 --> A1

    %% Update‑ForensicSuiteDev
    E2 --> P1
    P1 --> SD1
    SD1 --> SD2
    SD1 --> SD3
    SD3 --> SD4

    %% Repair‑Workspace
    E5 --> R1
    R1 --> C1
    R1 --> P1
    R1 --> SD3

    %% BuildSuiteSafe
    E3 --> C1
    E3 --> E4

    %% BuildSuite
    E4 --> P1
    E4 --> BS3
    BS3 --> BS4
    BS4 --> BS5
    BS5 --> BS6
    BS6 --> BS7
    BS7 --> BS8

    %% Deploy
    E6 --> D1
    E7 --> D1
    D1 --> D2
    D1 --> D3

    %% Preflight always calls Combined Validator
    P1 --> A1

    %% Sync‑Dev post‑apply validation uses RepoB strict rules
    SD4 --> A1
