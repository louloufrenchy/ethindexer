# Sync-Cluster.ps1
param (
    [string]$TargetHost 
)

# Load your manifest - ensuring we use 'hosts' to match your JSON structure
$manifest = Get-Content ".\scripts\orchestrator\deployment_manifest.json" | ConvertFrom-Json

# Access the 'hosts' array correctly
$nodesToSync = if ($TargetHost) {
    $manifest.hosts | Where-Object { $_.ip -eq $TargetHost.Trim() }
} else {
    $manifest.hosts
}

if (-not $nodesToSync) {
    Write-Error "No matching host found in manifest for '$TargetHost'"
    exit
}

$sourcePath = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"

foreach ($node in $nodesToSync) {
    # Based on your 'net use' output, we know 192.168.0.28 is I:
    # We set the destination to the drive letter directly
    if ($node.ip -eq "192.168.0.28") {
        $destination = "I:\LAPTOP-229C74PJ\Development\forensic_tracer_installer_project_root"
        Write-Host ">>> Syncing to: $($node.name) via existing mapping I:" -ForegroundColor Green
    } 
    elseif ($node.ip -eq "192.168.0.xxx") { # Placeholder for your other mapped IPs
        $destination = "J:\ForensicSuiteV2"
        Write-Host ">>> Syncing to: $($node.name) via existing mapping J:" -ForegroundColor Green
    }
    else {
        # Fallback to UNC path if no local mapping exists
        $destination = "\\$($node.ip)\f$\ForensicSuiteV2"
        Write-Host ">>> Syncing to: $($node.name) via UNC path" -ForegroundColor Yellow
    }

    # Run Robocopy
    # /MT:32 - Uses 32 threads for maximum transfer speed
    # /TBD - Robustly waits for the network name to resolve
    robocopy $sourcePath $destination /E /Z /XO /XD venv /XF unins* /MT:32 /R:3 /W:5 /TBD /NP
}
