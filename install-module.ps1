param(
    [string]$Root = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"
)

$moduleSource = Join-Path $Root "ForensicSuite.Orchestrator"
$moduleDest   = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\ForensicSuite.Orchestrator"

if (-not (Test-Path $moduleSource)) {
    throw "Module source not found: $moduleSource. Run bootstrap.ps1 first."
}

if (-not (Test-Path $moduleDest)) {
    New-Item -ItemType Directory -Path $moduleDest | Out-Null
}

Write-Host "Copying module from $moduleSource to $moduleDest"
Copy-Item -Path "$moduleSource\*" -Destination $moduleDest -Recurse -Force

Write-Host "Module installed. Testing import..." -ForegroundColor Cyan
Import-Module ForensicSuite.Orchestrator -Force

Write-Host "Module imported successfully." -ForegroundColor Green
