<#
.SYNOPSIS
    Validates ingestion progress on a remote host by checking block height movement
    across BTC, ETH, and TRON indexer logs.

.DESCRIPTION
    - Uses Using Module (lexical import)
    - No $PSScriptRoot
    - No colon interpolation
    - Clean literal here-string
    - StrictMode-safe
    - Deterministic remote execution
#>

# ---------------------------------------------------------------------------
# Lexical module import — guaranteed visible inside this script
# ---------------------------------------------------------------------------
Using Module "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root\scripts\ForensicSuite.Validation.psm1"

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetHost,

    [int]$WaitSeconds = 30
)

# ---------------------------------------------------------------------------
# Now safe to print output
# ---------------------------------------------------------------------------
Write-Host "=== Ingestion Progress Test on $TargetHost ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Literal here-string (single quotes) — NOTHING is interpolated locally
# ---------------------------------------------------------------------------
$script = @'
$ErrorActionPreference = "Stop"

$logs = @{
    btc  = "C:\forensic_suite_logs\btc_indexer.out.log"
    eth  = "C:\forensic_suite_logs\eth_indexer.out.log"
    tron = "C:\forensic_suite_logs\tron_indexer.out.log"
}

function Get-LastHeight {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    $lines = Get-Content $Path -Tail 200

    # Regex supports:
    #   height=12345
    #   block_height: 12345
    #   "height": 12345
    $regex = 'height[^\d]*(\d+)|block[_ ]height[^\d]*(\d+)'

    $matches = $lines | Select-String -Pattern $regex -AllMatches
    if (-not $matches) { return $null }

    $nums = @()
    foreach ($m in $matches.Matches) {
        foreach ($g in $m.Groups) {
            if ($g.Value -match '^\d+$') {
                $nums += [int]$g.Value
            }
        }
    }

    if ($nums.Count -eq 0) { return $null }
    return ($nums | Sort-Object -Descending | Select-Object -First 1)
}

# Capture heights at T0
$before = @{}
foreach ($k in $logs.Keys) {
    $before[$k] = Get-LastHeight -Path $logs[$k]
}

Start-Sleep -Seconds WAIT_SECONDS_PLACEHOLDER

# Capture heights at T1
$after = @{}
foreach ($k in $logs.Keys) {
    $after[$k] = Get-LastHeight -Path $logs[$k]
}

# Build result objects
$result = foreach ($k in $logs.Keys) {
    $b = $before[$k]
    $a = $after[$k]
    $delta = if ($b -ne $null -and $a -ne $null) { $a - $b } else { $null }

    [pscustomobject]@{
        Chain  = $k.ToUpper()
        Before = $b
        After  = $a
        Delta  = $delta
    }
}

$result
'@

# Inject wait seconds safely (string replace)
$script = $script.Replace("WAIT_SECONDS_PLACEHOLDER", $WaitSeconds.ToString())


# ---------------------------------------------------------------------------
# Execute remote script
# ---------------------------------------------------------------------------
try {
    $result = Invoke-RemotePS -Host $TargetHost -Script $script
}
catch {
    throw ("Remote ingestion test failed on {0}: {1}" -f $TargetHost, $_.Exception.Message)
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
$result | Format-Table -AutoSize
