function Read-OrchestrationManifest {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Manifest not found: $Path"
    }

    Import-PowerShellDataFile -Path $Path
}
