# Disable-Debug.ps1 - Global Hardening
$ProjectRoot = "C:\development\forensic_tracer_installer_project_root\forensic_suite_v2"

# Target ALL Python files to catch rogue imports in API and core scripts
$targetFiles = Get-ChildItem -Path $ProjectRoot -Filter "*.py" -Recurse

Write-Host ">>> Disabling all debugpy references globally..." -ForegroundColor Cyan

foreach ($file in $targetFiles) {
    $content = Get-Content $file.FullName
    if ($content -match "debugpy") {
        Write-Host "Patching: $($file.FullName -replace 'C:\\development\\', '')" -ForegroundColor Gray
        $updatedContent = $content | ForEach-Object {
            # Catch imports, listen calls, and wait_for_client triggers
            if ($_ -match "^\s*(import debugpy|from debugpy|debugpy\.|print\(.*debugger attach.*)") {
                "# " + $_.TrimStart("# ") # Avoid double-commenting
            } else {
                $_
            }
        }
        $updatedContent | Set-Content $file.FullName
    }
}
Write-Host ">>> Global Cleanup complete." -ForegroundColor Green
