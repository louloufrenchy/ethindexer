Operational Automation for Forensic Suite V2
This folder contains all developer‑facing and operator‑facing automation for maintaining a deterministic, reproducible development and deployment workflow across:

Repo A (authoritative development repo)  
F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root

Repo B (deployable mirror repo)  
F:\DEVELOPMENT\Repo_B\forensic_suite_v2

Repo A contains the real suite source code under:

forensic_suite_v2\

Repo B contains the deployable mirror of the suite under:

forensic_suite_v2\forensic_suite_v2\

Repo B also contains top‑level deployment scripts (e.g., deploy_suite.ps1, healthcheck.ps1) that must be preserved.

The scripts in this folder ensure Repo B always matches Repo A exactly for the suite, while preserving deployment‑only files.

🔍 1. forensic_suite_repo_mapping.ps1
Purpose: Generate a full file‑level mapping between Repo A and Repo B.

Outputs:  
F:\tools\repo_mapping.csv

What it does:

Walks both repos recursively

Computes relative paths

Computes SHA256 hashes

Marks each file as:

Present only in Repo A

Present only in Repo B

Present in both but different (drift)

Present in both and identical

Use when:

You want a forensic snapshot of repo divergence

Before running Sync‑DevTrees.Apply

Before or after a reinstall to confirm drift

📋 2. Sync-DevTrees.ps1 (Proposal Mode)
Purpose: Show what would change in Repo B without modifying anything.

What it prints:

Files/folders that would be deleted

Files that would be copied from Repo A → Repo B

Files that would be overwritten due to drift

Files that would remain untouched

Use when:

Running Sync-Dev from your PowerShell profile

Reviewing changes before applying

Validating mapping logic

This script is always safe.  
It never deletes or copies anything.

🟦 3. Sync-DevTrees.DryRun.ps1
Purpose: Print the exact PowerShell commands that Apply mode would execute.

What it prints:

Remove-Item commands for deletions

Copy-Item commands for missing files

Copy-Item -Force commands for drift overwrites

Directory creation commands (New-Item -ItemType Directory)

Use when:

You want to see the literal commands before applying

You want to audit the sync plan

You want to compare against previous runs

This script is also 100% safe.

🟩 4. Sync-DevTrees.Apply.ps1
Purpose: Perform the authoritative Repo A → Repo B sync.

Workflow:

Runs the Dry‑Run internally

Prints the exact commands

Prompts for confirmation

Creates a timestamped backup of Repo B under:

F:\tools\RepoB_Backups\RepoB_YYYYMMDD_HHMMSS\

Deletes only safe items (e.g., egg‑info)

Copies missing files from Repo A → Repo B

Overwrites drifted files

Leaves deployment‑only scripts untouched

Use when:

You want Repo B to become a perfect mirror of Repo A

Before building a new installer

Before running a reinstall on hosts

Before blue/green slot switching

This is the authoritative sync engine.

🟧 5. Sync-DevTrees.Rollback.ps1
Purpose: Restore Repo B from a timestamped backup created by Apply mode.

What it does:

Lists available backups

Restores Repo B from the chosen timestamp

Overwrites Repo B safely

Use when:

A sync introduced unexpected changes

You want to revert Repo B to a known‑good state

You want to test multiple sync strategies

🟨 6. Sync-DevTrees.Validate.ps1
Purpose: Confirm Repo B matches Repo A exactly for the suite.

What it checks:

Missing files in Repo B

Extra files in Repo B

Drifted files (hash mismatch)

Identical files

Use when:

After Apply mode

After rollback

Before building an installer

Before running a reinstall

Before switching blue/green slots

If validation passes:  
Repo B is a byte‑for‑byte mirror of Repo A for the suite.

🧩 7. How these scripts integrate with your $PROFILE Sync‑Dev
Your PowerShell profile should contain:

function Sync-Dev {
    Write-Host "`n>>> Syncing Suite Trees (Proposal Mode)..." -ForegroundColor Cyan
    & "$Global:PrimaryRoot\scripts\Sync-DevTrees.ps1"
    Write-Host "[INFO] Review the proposal above. Run Sync-DevTrees.Apply.ps1 to execute." -ForegroundColor Yellow

    Write-Host "`n>>> Syncing Python Environment (Editable Install)..." -ForegroundColor Cyan
    Push-Location $Global:PrimaryRoot
    python -m pip install -e .
    Pop-Location
    Write-Host "[SUCCESS] ForensicSuite package refreshed." -ForegroundColor Green
}

This ensures:

Every developer sees the proposal before applying

No accidental destructive syncs

Python editable install is always refreshed

🧭 8. Operational workflow (recommended)
Daily development

Sync-Dev

Before building installer

Sync-DevTrees.Apply.ps1
Sync-DevTrees.Validate.ps1

Before reinstalling on hosts

Sync-DevTrees.Apply.ps1
Sync-DevTrees.Validate.ps1

If something goes wrong

Sync-DevTrees.Rollback.ps1

🛡️ 9. Safety guarantees
These scripts guarantee:

Repo A is always authoritative

Repo B is always a clean deployable mirror

No accidental deletion of deployment scripts

No accidental deletion of installer payload

Full backup before any destructive action

Full validation after sync

Full reversibility via rollback
