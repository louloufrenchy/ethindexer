# =====================================================================
# FORENSIC SUITE V2 - MASTER DEVELOPMENT PROFILE (V9.3.2 - STABLE, ENHANCED)
# =====================================================================

# --- GLOBAL CONSTANTS ------------------------------------------------
$Global:PrimaryRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"
$Global:ClusterIPs = @("192.168.0.199", "192.168.0.28", "192.168.0.146", "192.168.0.165")
$Global:SSHKey = "$env:USERPROFILE\.ssh\id_ed25519"
$Global:HostList = "F:\tools\forensic_hosts.txt"

# Credentials (prompt once per session)
$Global:Creds = @{
    "192.168.0.146" = Get-Credential "SELVON\forensicuser"
    "192.168.0.199" = Get-Credential "WIN-1V7900SUQ9A\forensicuser"
    "192.168.0.165" = Get-Credential "WIN-8ENVN7I0JFE\forensicuser"
    "192.168.0.28"  = Get-Credential "Louis-HP\forensicuser"
}

# Add to path
# Add Sysinternals tools to PATH
$tools = "F:\tools"
if (-not ($env:PATH -split ";" | Where-Object { $_ -eq $tools })) {
    $env:PATH = "$tools;$env:PATH"
}

\
# =====================================================================
# 0. VALIDATION MODULE AUTO-IMPORT (V9.3)
# =====================================================================

# Preferred: import by module name if installed somewhere in $env:PSModulePath
$ValidationModuleName = "ForensicSuite.Validation"

# Fallback: import directly from your dev repo (adjust if your repo lives elsewhere)
$ValidationModulePath = Join-Path $Global:PrimaryRoot "scripts\ForensicSuite.Validation.psm1"

try {
    if (Get-Module -ListAvailable -Name $ValidationModuleName) {
        Import-Module $ValidationModuleName -Force -ErrorAction Stop
    }
    elseif (Test-Path $ValidationModulePath) {
        Import-Module $ValidationModulePath -Force -ErrorAction Stop
    }
    else {
        Write-Host "[WARNING] Validation module not found. Install it under a PSModulePath location, or place it here:`n  $ValidationModulePath" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[ERROR] Failed to import validation module: $($_.Exception.Message)" -ForegroundColor Red
}

# Convenience aliases
Set-Alias cleanall Clear-ForensicSuiteAll
Set-Alias validate Test-ForensicSuiteAll
Set-Alias repair Repair-Workspace
Set-Alias safe-build Invoke-BuildSuiteSafe
Set-Alias syncdev Update-ForensicSuiteDev


Write-Host "`nForensic Suite Workspace V9.3 Loaded." -ForegroundColor Yellow
