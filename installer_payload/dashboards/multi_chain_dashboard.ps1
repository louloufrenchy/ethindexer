$env:PGPASSWORD = "Str0ngPassw0rd2025"
while ($true) {
    Clear-Host

    $result = psql -h 127.0.0.1 -p 5432 -U postgres -d forensic -t -A -F"," -c @"
SELECT
    chain,
    last_block,
    (SELECT chain_head FROM indexer_metrics m 
        WHERE m.chain = c.chain ORDER BY ts DESC LIMIT 1) AS head_block
FROM index_checkpoint c
WHERE chain IN ('btc','eth','tron')
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

