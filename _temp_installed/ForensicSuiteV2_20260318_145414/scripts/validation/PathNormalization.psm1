# PathNormalization.psm1
# Centralized path resolver for Repo A and Repo B

# --- ROOTS -------------------------------------------------------------

$Global:PrimaryRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"
$Global:RepoB       = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
$Global:Tools       = "F:\tools"
$Global:Secrets     = "F:\forensic_secrets"

# --- RESOLVED PATHS ----------------------------------------------------

function Get-RepoARoot { return $Global:PrimaryRoot }
function Get-RepoBRoot { return $Global:RepoB }
function Get-ToolsRoot { return $Global:Tools }
function Get-SecretsRoot { return $Global:Secrets }

function Get-InstallerPayloadRoot {
    return Join-Path $Global:PrimaryRoot "installer_payload"
}

function Get-ScriptsRoot {
    return Join-Path $Global:PrimaryRoot "scripts"
}

function Get-ConfigRoot {
    return Join-Path $Global:PrimaryRoot "config"
}

function Get-OutRoot {
    return Join-Path $Global:PrimaryRoot "out"
}

# --- VALIDATION --------------------------------------------------------

function Test-PathNormalization {
    Write-Host "=== Path Normalization Check ===" -ForegroundColor Cyan

    $paths = @{
        "PrimaryRoot" = $Global:PrimaryRoot
        "RepoB"       = $Global:RepoB
        "Tools"       = $Global:Tools
        "Secrets"     = $Global:Secrets
    }

    foreach ($k in $paths.Keys) {
        $p = $paths[$k]
        if (Test-Path $p) {
            Write-Host "[OK] $k → $p" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] $k → $p (missing)" -ForegroundColor Red
        }
    }
}
