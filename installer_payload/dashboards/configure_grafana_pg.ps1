param(
    [string]$GrafanaUrl = "http://localhost:3000",
    [string]$AdminUser = "admin",
    [string]$AdminPassword = "admin",
    [string]$PgHost = "localhost",
    [int]$PgPort = 5432,
    [string]$PgDatabase = "tron_index",
    [string]$PgUser = "tron",
    [string]$PgPassword = "tronpass"
)

Write-Host "[*] Configuring Grafana PostgreSQL datasource 'PG_TRON_INDEX'..."

$authToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$AdminUser`:$AdminPassword"))
$headers = @{
    "Authorization" = "Basic $authToken"
    "Content-Type"  = "application/json"
}

$body = @{
    name   = "PG_TRON_INDEX"
    type   = "postgres"
    access = "proxy"
    url    = "$PgHost`:$PgPort"
    user   = $PgUser
    database = $PgDatabase
    isDefault = $false
    jsonData = @{
        sslmode = "disable"
    }
    secureJsonData = @{
        password = $PgPassword
    }
} | ConvertTo-Json -Depth 5

$resp = Invoke-RestMethod -Method Post -Uri "$GrafanaUrl/api/datasources" -Headers $headers -Body $body -ErrorAction Stop

Write-Host "[+] Datasource created/updated:"
$resp | ConvertTo-Json -Depth 5
