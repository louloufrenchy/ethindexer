$serviceName = "TronIndexerService"
$lastBlockFile = "C:\tron_indexer\logs\last_block.txt"

while ($true) {
    if (-Not (Test-Path $lastBlockFile)) {
        Start-Sleep -Seconds 60
        continue
    }

    $last = Get-Content $lastBlockFile

    Start-Sleep -Seconds 120

    $current = Get-Content $lastBlockFile

    if ($current -eq $last) {
        Restart-Service -Name $serviceName
    }
}
