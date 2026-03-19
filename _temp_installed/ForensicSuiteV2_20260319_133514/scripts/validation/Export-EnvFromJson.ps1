param(
    [string]$SecretsRoot = 'C:\forensic_secrets'
)

$jsonPath = Join-Path $SecretsRoot 'env.json'
$envPath  = Join-Path $SecretsRoot '.env'

if (-not (Test-Path $jsonPath)) {
    throw "env.json not found at $jsonPath"
}

$config = Get-Content $jsonPath -Raw | ConvertFrom-Json

$lines = @()

# Postgres
$lines += '# Postgres'
$lines += "PGPASSWORD=$($config.postgres.password)"
$lines += ''

# Ethereum
$lines += '# Ethereum'
$lines += "QUICKNODE_ETH_HTTP=$($config.eth.rpc_http)"
$lines += "QUICKNODE_ETH_WSS=$($config.eth.rpc_wss)"
$lines += "QUICKNODE_ETH_ENDPOINT_1=$($config.eth.rpc_url_1)"
$lines += "QUICKNODE_ETH_ENDPOINT_2=$($config.eth.rpc_url_2)"
$lines += ''

# Tron
$lines += '# Tron'
$lines += "QUICKNODE_TRON_ENDPOINT_1=$($config.tron.grpc_endpoint)"
$lines += "QUICKNODE_TRON_ENDPOINT_2=$($config.tron.fullnode_endpoint)"
$lines += ''

# Bitcoin
$lines += '# Bitcoin'
$lines += "QUICKNODE_BTC_ENDPOINT_1=$($config.btc.rpc_url_1)"
$lines += "QUICKNODE_BTC_ENDPOINT_2=$($config.btc.rpc_url_2)"
$lines += ''

Set-Content -Path $envPath -Value $lines -Encoding UTF8

Write-Host "[OK] .env regenerated from env.json at $envPath"
