1. Diagram of the recovery flow
mermaid
flowchart TD

A[Start on host 28\nBroken repo copy] --> B[git status\nNot a repo / corrupted]
B --> C[Fix NTFS ACLs\nicacls .git ...]
C --> D[git init\nReconnect remote]
D --> E[git fetch origin]
E --> F[git checkout dev]
F --> G[git merge master]
G --> H{10k+ conflicts\n_temp_installed tracked?}

H -->|Yes| I[Add _temp_installed to .gitignore]
I --> J[git rm -r --cached _temp_installed]
J --> K[git commit\nRemove temp artifacts]
K --> L[Resolve real conflicts in VS Code]
L --> M[git add . / per file]
M --> N[git commit\nMerge branch 'master' into dev]
N --> O[git push origin dev]
O --> P[git status\nClean working tree]
2. Timeline of events
T0 — Initial state

Repo copied to host 28 via robocopy without .git.

Working tree had real changes, no Git metadata.

T1 — Git re‑init & ACL issues

git init, git remote add, git fetch attempted.

.git/objects write failures due to NTFS ACL corruption.

ACLs reset with icacls .git /reset and full rights granted.

T2 — Reconnect to origin

git checkout dev.

git status shows many modified/new files vs origin.

T3 — Merge attempt

git merge master into dev.

Explosion of 10,000+ conflicts due to _temp_installed being tracked.

T4 — Artifact cleanup

_temp_installed added to .gitignore.

git rm -r --cached _temp_installed.

Commit to remove temp artifacts from tracking.

T5 — Real conflict resolution

VS Code merge editor used to resolve real conflicts.

Files staged via git add / “Stage Changes”.

T6 — Merge commit

git commit opens COMMIT_EDITMSG.

Message: Merge branch 'master' into dev.

Save + close → [dev 8f8bc9c] Merge branch 'master' into dev.

T7 — Finalization

git push origin dev.

git status → clean working tree.

Repo fully recovered and unified.

3. Checklist for future migrations
Before migration

Verify remote health:

git status (clean)

git fetch --all

git pull (if needed)

Ensure artifacts are ignored:

.gitignore includes:

_temp_installed/

dist/, build/, venv/, __pycache__/, *.log, *.tmp, installer outputs.

Tag or branch:

Create a safety tag/branch:

git tag pre-migration-<date>

or git branch migration-<date>

During migration

Use Git, not raw file copy, when possible:

Prefer git clone on the new host.

If you must use robocopy:

Either:

Include .git fully, preserving ACLs

or explicitly treat the destination as a fresh clone and re‑init Git there.

Avoid partial .git copies.

Validate ACLs on arrival:

icacls .git /verify

If needed:

icacls .git /reset /t /c

icacls .git /grant:r "$($env:USERNAME):(OI)(CI)F" /t /c

After migration

Reconnect Git cleanly:

git init (if needed)

git remote add origin ...

git fetch origin

git checkout dev (or relevant branch)

Check for accidental artifacts:

git status → ensure no _temp_installed, Output, etc.

If present:

git rm -r --cached <artifact>

Add to .gitignore

Commit.

Test merge on a scratch branch first:

git switch -c merge-dryrun

git merge master

Resolve conflicts, validate.

If good, repeat on real branch or fast‑forward.

4. Validator script to prevent this from happening again
Here’s a PowerShell validator you can drop into scripts/validation/Test-GitWorkspaceHealth.ps1 (or similar).
It checks for:

missing .git

ACL issues

tracked artifact folders

dirty working tree before merge

powershell
param(
    [string]$RepoRoot = (Get-Location).Path
)

Write-Host "=== Git Workspace Health Check ===" -ForegroundColor Cyan
Write-Host "RepoRoot: $RepoRoot" -ForegroundColor DarkCyan

function Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Pass {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

# 1. Check .git presence
$gitDir = Join-Path $RepoRoot ".git"
if (-not (Test-Path $gitDir)) {
    Fail ".git directory not found. This is not a valid Git working tree."
} else {
    Pass ".git directory present."
}

# 2. Check basic Git status
Push-Location $RepoRoot
try {
    $status = git status 2>&1
} catch {
    Fail "git status failed. Git may not be initialized correctly."
}

if ($status -match "fatal:") {
    Fail "git status reported a fatal error:`n$status"
} else {
    Pass "git status executed successfully."
}

# 3. Check for obvious ACL issues on .git/objects
$objectsDir = Join-Path $gitDir "objects"
if (-not (Test-Path $objectsDir)) {
    Warn ".git/objects missing. Repository may be corrupted."
} else {
    try {
        $testFile = Join-Path $objectsDir "healthcheck.tmp"
        "test" | Out-File -FilePath $testFile -Encoding ASCII -ErrorAction Stop
        Remove-Item $testFile -ErrorAction Stop
        Pass "Write test to .git/objects succeeded (ACLs look OK)."
    } catch {
        Warn "Write test to .git/objects FAILED. ACLs may be broken. Consider running icacls reset."
    }
}

# 4. Check for tracked build artifacts / temp folders
$artifactPatterns = @(
    "_temp_installed",
    "temp_installed",
    "Output",
    "installer_payload/output",
    "dist",
    "build",
    "__pycache__",
    "venv",
    ".venv"
)

$trackedArtifacts = @()

foreach ($pattern in $artifactPatterns) {
    $result = git ls-files "*$pattern*" 2>$null
    if ($result) {
        $trackedArtifacts += $result
    }
}

if ($trackedArtifacts.Count -gt 0) {
    Warn "The following artifact-like paths appear to be tracked by Git:"
    $trackedArtifacts | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Warn "Consider: git rm -r --cached <path> and adding to .gitignore."
} else {
    Pass "No obvious artifact folders tracked by Git."
}

# 5. Check for uncommitted changes before merge
if ($status -match "nothing to commit, working tree clean") {
    Pass "Working tree is clean."
} else {
    Warn "Working tree is NOT clean. Review before merging or migrating."
    Write-Host $status
}

Pop-Location

Write-Host "=== Git Workspace Health Check Complete ===" -ForegroundColor Cyan