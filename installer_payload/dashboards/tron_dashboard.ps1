# ============================
# Load external secrets
# ============================
$secretPath = "C:\forensic_secrets\env.json"
if (Test-Path $secretPath) {
    $envData = Get-Content $secretPath | ConvertFrom-Json
    $env:PGPASSWORD = $envData.PGPASSWORD
} else {
    Write-Host "Missing secrets file: $secretPath" -ForegroundColor Red
    exit 1
}

while ($true) {
    Clear-Host

    # ============================
    # CONFIG
    # ============================
    $target = 45000000

    $result = psql -h 127.0.0.1 -p 5432 -U postgres -d forensic -t -A -F"," -c @"
WITH
checkpoint AS (
    SELECT last_indexed_block
    FROM index_checkpoint_tron
    ORDER BY id DESC
    LIMIT 1
),
blocks AS (
    SELECT COALESCE(MAX(height), 0) AS last_block_height
    FROM tron_block_hashes
),
metrics AS (
    SELECT metric_value AS head_block
    FROM ingestion_metrics
    WHERE chain_name = 'tron'
      AND metric_name = 'chain_head'
    ORDER BY created_at DESC
    LIMIT 1
)
SELECT
    checkpoint.last_indexed_block,
    blocks.last_block_height,
    metrics.head_block
FROM checkpoint, blocks, metrics;
"@

    if (-not $result) {
        Write-Host "No data returned from Postgres. Is the TRON indexer running?" -ForegroundColor Red
        Start-Sleep -Seconds 5
        continue
    }

    $fields = $result.Split(",")

    $lastIndexed = [int]$fields[0]
    $lastBlockRow = [int]$fields[1]
    $headBlock = [int]$fields[2]

    $lag = $headBlock - $lastIndexed
    $remaining = $target - $lastIndexed

    if ($remaining -gt 0) {
        $blocksPerSec = 200
        $etaSec = [math]::Max([math]::Floor($remaining / $blocksPerSec), 0)
        $eta = [TimeSpan]::FromSeconds($etaSec)
    } else {
        $eta = [TimeSpan]::FromSeconds(0)
    }

    $start = 0
    $total = $target - $start
    if ($total -le 0) { $total = 1 }

    $done = $lastIndexed - $start
    if ($done -lt 0) { $done = 0 }
    if ($done -gt $total) { $done = $total }

    $pct = [math]::Round(($done / $total) * 100, 2)

    $barLength = 40
    $filled = [math]::Floor(($pct / 100) * $barLength)
    $empty = $barLength - $filled

    $bar = ("█" * $filled) + ("░" * $empty)

    if ($pct -lt 50) { $color = "Yellow" }
    elseif ($pct -lt 90) { $color = "Cyan" }
    else { $color = "Green" }

    Write-Host "=== TRON Ingestion Dashboard (Unified Forensic DB) ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("Progress to target ({0}): [{1}] {2}%" -f $target, $bar, $pct) -ForegroundColor $color
    Write-Host ("ETA to target: {0}" -f $eta) -ForegroundColor Magenta
    Write-Host ""
    Write-Host ("Last indexed block (checkpoint): {0}" -f $lastIndexed) -ForegroundColor White
    Write-Host ("Last block in tron_block_hashes: {0}" -f $lastBlockRow) -ForegroundColor DarkGray
    Write-Host ("Chain head (metrics):            {0}" -f $headBlock) -ForegroundColor DarkGray
    Write-Host ("Ingestion lag vs head:           {0}" -f $lag) -ForegroundColor Yellow
    Write-Host ("Blocks until target:             {0}" -f $remaining) -ForegroundColor Green

    Start-Sleep -Seconds 5
}
