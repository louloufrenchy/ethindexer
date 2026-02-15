$env:PGPASSWORD = "Str0ngPassw0rd2025"

while ($true) {
    Clear-Host

    $target = 41410173

    # Query unified forensic DB
    $result = psql -h 127.0.0.1 -p 5432 -U postgres -d forensic -t -A -F"," -c @"
WITH
checkpoint AS (
    SELECT last_block AS last_indexed_block
    FROM index_checkpoint
    WHERE id = 3   -- TRON CHECKPOINT
),
trc20 AS (
    SELECT COALESCE(MAX(block_number), 0) AS last_trc20_block
    FROM trc20_transfers
),
addr AS (
    SELECT COALESCE(MAX(block_number), 0) AS last_address_index_block
    FROM address_tx_index
),
metrics AS (
    SELECT chain_head AS head_block
    FROM indexer_metrics
    WHERE chain = 'tron'
    ORDER BY ts DESC
    LIMIT 1
)
SELECT
    checkpoint.last_indexed_block,
    trc20.last_trc20_block,
    addr.last_address_index_block,
    metrics.head_block
FROM checkpoint, trc20, addr, metrics;
"@

    if (-not $result) {
        Write-Host "No data returned from Postgres. Is the TRON indexer running?" -ForegroundColor Red
        Start-Sleep -Seconds 5
        continue
    }

    $fields = $result.Split(",")

    $lastIndexed = [int]$fields[0]
    $lastTRC20   = [int]$fields[1]
    $lastAddr    = [int]$fields[2]
    $headBlock   = [int]$fields[3]

    $lag = $headBlock - $lastIndexed
    $remaining = $target - $lastIndexed

    # ETA calculation
    if ($lag -gt 0) {
        $blocksPerSec = 100   # tune based on your host
        $etaSec = [math]::Max([math]::Floor($remaining / $blocksPerSec), 0)
        $eta = [TimeSpan]::FromSeconds($etaSec)
    } else {
        $eta = "0"
    }

    # Progress bar
    $start = 41402306
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

    # Color logic
    if ($pct -lt 50) { $color = "Yellow" }
    elseif ($pct -lt 90) { $color = "Cyan" }
    else { $color = "Green" }

    Write-Host "=== TRON Ingestion Dashboard (Enhanced) ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("Progress: [{0}] {1}%" -f $bar, $pct) -ForegroundColor $color
    Write-Host ("ETA to target: {0}" -f $eta) -ForegroundColor Magenta
    Write-Host ""
    Write-Host ("Last indexed block:        {0}" -f $lastIndexed) -ForegroundColor White
    Write-Host ("Last TRC20 block:          {0}" -f $lastTRC20) -ForegroundColor DarkGray
    Write-Host ("Last address index block:  {0}" -f $lastAddr) -ForegroundColor DarkGray
    Write-Host ("Chain head:                {0}" -f $headBlock) -ForegroundColor DarkGray
    Write-Host ("Ingestion lag:             {0}" -f $lag) -ForegroundColor Yellow
    Write-Host ("Blocks until target:       {0}" -f $remaining) -ForegroundColor Green

    Start-Sleep -Seconds 5
}
