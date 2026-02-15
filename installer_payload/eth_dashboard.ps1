$env:PGPASSWORD = "Str0ngPassw0rd2025"

while ($true) {
    Clear-Host

    # ============================
    # CONFIG
    # ============================
    # Set your ETH target block here (example)
    $target = 22000000

    # Query DB (unified forensic DB)
    $result = psql -h 127.0.0.1 -p 5432 -U postgres -d forensic -t -A -F"," -c @"
WITH
checkpoint AS (
    SELECT last_block AS last_indexed_block
    FROM index_checkpoint
    WHERE id = 2  -- ETH checkpoint
),
blocks AS (
    SELECT COALESCE(MAX(block_number), 0) AS last_block_height
    FROM eth_blocks
),
metrics AS (
    SELECT chain_head AS head_block
    FROM indexer_metrics
    WHERE chain = 'eth'
    ORDER BY ts DESC
    LIMIT 1
)
SELECT
    checkpoint.last_indexed_block,
    blocks.last_block_height,
    metrics.head_block
FROM checkpoint, blocks, metrics;
"@

    if (-not $result) {
        Write-Host "No data returned from Postgres. Is the ETH indexer running?" -ForegroundColor Red
        Start-Sleep -Seconds 5
        continue
    }

    # ============================
    # PARSE FIELDS
    # ============================
    $fields = $result.Split(",")

    $lastIndexed  = [int]$fields[0]  # from index_checkpoint (id=2)
    $lastBlockRow = [int]$fields[1]  # max(eth_blocks.block_number)
    $headBlock    = [int]$fields[2]  # from indexer_metrics

    $lag       = $headBlock - $lastIndexed
    $remaining = $target - $lastIndexed

    # ============================
    # ETA CALCULATION
    # ============================
    if ($remaining -gt 0) {
        # ETH ~12–15 blocks/sec; tune as needed
        $blocksPerSec = 15
        $etaSec = [math]::Max([math]::Floor($remaining / $blocksPerSec), 0)
        $eta = [TimeSpan]::FromSeconds($etaSec)
    } else {
        $eta = [TimeSpan]::FromSeconds(0)
    }

    # ============================
    # PROGRESS BAR
    # ============================
    # Define a sliding window start (e.g. last 500k blocks)
    $startBlock = $target - 500000
    if ($startBlock -lt 0) { $startBlock = 0 }

    $total = $target - $startBlock
    if ($total -le 0) { $total = 1 }

    $done = $lastIndexed - $startBlock
    if ($done -lt 0) { $done = 0 }
    if ($done -gt $total) { $done = $total }

    $pct = [math]::Round(($done / $total) * 100, 2)

    $barLength = 40
    $filled = [math]::Floor(($pct / 100) * $barLength)
    $empty  = $barLength - $filled

    $bar = ("█" * $filled) + ("░" * $empty)

    # ============================
    # COLOR LOGIC
    # ============================
    if ($pct -lt 50) { $color = "Yellow" }
    elseif ($pct -lt 90) { $color = "Cyan" }
    else { $color = "Green" }

    # ============================
    # OUTPUT
    # ============================
    Write-Host "=== ETH Ingestion Dashboard (Enhanced) ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("Progress to target ({0}): [{1}] {2}%" -f $target, $bar, $pct) -ForegroundColor $color
    Write-Host ("ETA to target: {0}" -f $eta) -ForegroundColor Magenta
    Write-Host ""
    Write-Host ("Last indexed block (checkpoint): {0}" -f $lastIndexed) -ForegroundColor White
    Write-Host ("Last block in eth_blocks:        {0}" -f $lastBlockRow) -ForegroundColor DarkGray
    Write-Host ("Chain head (metrics):            {0}" -f $headBlock) -ForegroundColor DarkGray
    Write-Host ("Ingestion lag vs head:           {0}" -f $lag) -ForegroundColor Yellow
    Write-Host ("Blocks until target:             {0}" -f $remaining) -ForegroundColor Green

    Start-Sleep -Seconds 5
}
