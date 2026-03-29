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
