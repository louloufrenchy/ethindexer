$env:PGPASSWORD = "Str0ngPassw0rd2025"

while ($true) {
    Clear-Host

    $result = psql -h 127.0.0.1 -p 5432 -U postgres -d forensic -t -A -F"," -c @"
SELECT
    chain,
    last_indexed_block,
    (SELECT metric_value FROM ingestion_metrics m
        WHERE m.chain_name = c.chain
        AND m.metric_name = 'chain_head'
        ORDER BY created_at DESC LIMIT 1) AS head_block
FROM (
    SELECT 'btc' AS chain, last_indexed_block FROM btc_index_checkpoint
    UNION ALL
    SELECT 'eth', last_indexed_block FROM eth_index_checkpoint
    UNION ALL
    SELECT 'tron', last_indexed_block FROM index_checkpoint_tron
) c
ORDER BY CASE chain
    WHEN 'btc' THEN 1
    WHEN 'eth' THEN 2
    WHEN 'tron' THEN 3
END;
"@

    $lines = $result -split "`n"

    Write-Host "=== Multi-Chain Dashboard (BTC / ETH / TRON) ===" -ForegroundColor Cyan
    Write-Host ""

    foreach ($line in $lines) {
        if ($line.Trim() -eq "") { continue }

        $f = $line.Split(",")

        $chain = $f[0]
        $last  = [int]$f[1]
        $head  = [int]$f[2]
        $lag   = $head - $last

        if ($lag -lt 1000) { $color = "Green" }
        elseif ($lag -lt 10000) { $color = "Yellow" }
        else { $color = "Red" }

        Write-Host ("{0,-6} | Last: {1,-10} | Head: {2,-10} | Lag: {3,-10}" -f $chain.ToUpper(), $last, $head, $lag) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "Refresh every 5 seconds..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
}
