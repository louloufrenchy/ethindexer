param(
    [string]$HostIp,
    [string]$ConfigPath = "C:\forensic_suite_v2\forensic_suite_v2\config\indexer.yaml"
)

$ErrorActionPreference = "Stop"

function Resolve-LocalHostIp {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -like "192.168.*" -and $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -First 1 -ExpandProperty IPAddress

    if (-not $ip) {
        throw "Could not resolve local 192.168.x.x IPv4 address."
    }

    return $ip
}

if (-not $HostIp) {
    $HostIp = Resolve-LocalHostIp
}

Write-Host "=== Chain Toggle ==="
Write-Host "Host: $HostIp"
Write-Host "ConfigPath: $ConfigPath"

$map = @{
    "192.168.0.165" = @{ eth = $true;  tron = $false; btc = $false }
    "192.168.0.172" = @{ eth = $false; tron = $true;  btc = $false }
    "192.168.0.199" = @{ eth = $false; tron = $false; btc = $true  }
    "192.168.0.28"  = @{ eth = $false; tron = $false; btc = $false }
}

if (-not $map.ContainsKey($HostIp)) {
    throw "No mapping for host IP $HostIp"
}

if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$target = $map[$HostIp]
$lines = Get-Content $ConfigPath

function Set-Enabled {
    param(
        [string]$Chain,
        [bool]$Value
    )

    $inside = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$Chain\s*:") {
            $inside = $true
            continue
        }

        if ($inside -and $lines[$i] -match "^\S") {
            break
        }

        if ($inside -and $lines[$i] -match "^\s*enabled\s*:") {
            if ($Value) {
                $lines[$i] = "  enabled: true"
            }
            else {
                $lines[$i] = "  enabled: false"
            }
            break
        }
    }
}

Set-Enabled "eth"  $target.eth
Set-Enabled "tron" $target.tron
Set-Enabled "btc"  $target.btc

$lines | Set-Content $ConfigPath -Encoding UTF8

Write-Host "Result:"
Write-Host "eth=$($target.eth) tron=$($target.tron) btc=$($target.btc)"
Write-Host "[OK] YAML updated"
