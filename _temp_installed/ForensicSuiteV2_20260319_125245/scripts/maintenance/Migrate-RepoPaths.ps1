[CmdletBinding()]
param(
    [string]$RepoRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root",
    [string]$NewPrimaryRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root",
    [string]$NewRepoB = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2",
    [string]$NewToolsRoot = "F:\tools",
    [string]$NewSecretRoot = "F:\forensic_secrets",
    [switch]$Report,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (($Report -and $Apply) -or (-not $Report -and -not $Apply)) {
    throw "Specify exactly one of: -Report or -Apply"
}

Write-Host "=== Repo Path Migration ===" -ForegroundColor Cyan
Write-Host "RepoRoot       : $RepoRoot" -ForegroundColor Gray
Write-Host "NewPrimaryRoot : $NewPrimaryRoot" -ForegroundColor Gray
Write-Host "NewRepoB       : $NewRepoB" -ForegroundColor Gray
Write-Host "NewToolsRoot   : $NewToolsRoot" -ForegroundColor Gray
Write-Host "NewSecretRoot  : $NewSecretRoot" -ForegroundColor Gray
Write-Host "Mode           : $(if ($Report) { 'REPORT' } else { 'APPLY' })" -ForegroundColor Gray

if (-not (Test-Path $RepoRoot)) {
    throw "RepoRoot not found: $RepoRoot"
}

$AllowedExtensions = @(
    ".ps1", ".psm1", ".psd1",
    ".py",
    ".cmd", ".bat",
    ".iss",
    ".json",
    ".yaml", ".yml",
    ".cfg",
    ".txt",
    ".md"
)

$SkipPathPatterns = @(
    "\dist\",
    "\build\",
    "\_temp_installed\",
    "\backup_forensic_suite_v2_",
    "\installer_payload\forensic_suite_v2\",
    "\.git\",
    "\venv\",
    "\_pycache_\"
)

$ReplacementMap = [ordered]@{
    "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root" = $NewPrimaryRoot
    "F:/DEVELOPMENT/Repo_A/forensic_tracer_installer_project_root" = ($NewPrimaryRoot -replace "\\","/")
    "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"                      = $NewRepoB
    "F:/DEVELOPMENT/Repo_B/forensic_suite_v2"                      = ($NewRepoB -replace "\\","/")
    "F:\tools"                                              = $NewToolsRoot
    "F:/tools"                                              = ($NewToolsRoot -replace "\\","/")
    "F:\forensic_secrets"                                   = $NewSecretRoot
    "F:/forensic_secrets"                                   = ($NewSecretRoot -replace "\\","/")
    "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root" = $NewPrimaryRoot
    "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"                      = $NewRepoB
    "F:\tools"                                                     = $NewToolsRoot
    "F:\forensic_secrets"                                          = $NewSecretRoot
    "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"                = $NewPrimaryRoot
    "F:/DEVELOPMENT/Repo_A/forensic_tracer_installer_project_root"                = ($NewPrimaryRoot -replace "\\","/")
    "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"                                     = $NewRepoB
    "F:/DEVELOPMENT/Repo_B/forensic_suite_v2"                                     = ($NewRepoB -replace "\\","/")
    "F:\tools"                                                                    = $NewToolsRoot
    "F:/tools"                                                                    = ($NewToolsRoot -replace "\\","/")
    "F:\forensic_secrets"                                                         = $NewSecretRoot
    "F:/forensic_secrets"                                                         = ($NewSecretRoot -replace "\\","/")
}

$files = Get-ChildItem -Path $RepoRoot -Recurse -File | Where-Object {
    $_.Extension -in $AllowedExtensions
} | Where-Object {
    $full = $_.FullName
    -not ($SkipPathPatterns | Where-Object { $full -like "$_" })
}

if (-not $files) {
    Write-Warning "No candidate files found."
    exit 0
}

$results = New-Object System.Collections.Generic.List[object]
$changedFiles = New-Object System.Collections.Generic.HashSet[string]

foreach ($file in $files) {
    [string[]]$lines = @(Get-Content -Path $file.FullName)
    $fileChanged = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $originalLine = $lines[$i]
        $updatedLine = $originalLine

        foreach ($oldPath in $ReplacementMap.Keys) {
            $newPath = $ReplacementMap[$oldPath]
            $updatedLine = $updatedLine.Replace($oldPath, $newPath)
        }

        if ($updatedLine -ne $originalLine) {
            $fileChanged = $true

            $record = [pscustomobject]@{
                File         = $file.FullName
                LineNumber   = $i + 1
                OriginalLine = $originalLine
                UpdatedLine  = $updatedLine
            }
            [void]$results.Add($record)

            if ($Apply) {
                $lines[$i] = $updatedLine
            }
        }
    }

    if ($fileChanged) {
        [void]$changedFiles.Add($file.FullName)

        if ($Apply) {
            Set-Content -Path $file.FullName -Value $lines -Encoding UTF8
        }
    }
}

Write-Host ""
if ($results.Count -eq 0) {
    Write-Host "[OK] No matching old development paths found." -ForegroundColor Green
}
else {
    Write-Host ("[OK] Matched lines : {0}" -f $results.Count) -ForegroundColor Green
    Write-Host ("[OK] Affected files: {0}" -f $changedFiles.Count) -ForegroundColor Green
    Write-Host ""

    $results |
        Sort-Object File, LineNumber |
        Format-List File, LineNumber, OriginalLine, UpdatedLine
}

Write-Host ""
Write-Host "=== Residual Old-Path Scan ===" -ForegroundColor Cyan

$ResidualPatterns = @(
    "C:\\development\\forensic_tracer_installer_project_root",
    "F:/DEVELOPMENT/Repo_A/forensic_tracer_installer_project_root",
    "C:\\development\\forensic_suite_v2",
    "F:/DEVELOPMENT/Repo_B/forensic_suite_v2",
    "I:\\DEVELOPMENT\\Repo_A\\forensic_tracer_installer_project_root",
    "F:/DEVELOPMENT/Repo_A/forensic_tracer_installer_project_root",
    "I:\\DEVELOPMENT\\Repo_B\\forensic_suite_v2",
    "F:/DEVELOPMENT/Repo_B/forensic_suite_v2",
    "\\\\192\\.168\\.0\\.28\\f\\$\\DEVELOPMENT\\Repo_A\\forensic_tracer_installer_project_root",
    "\\\\192\\.168\\.0\\.28\\f\\$\\DEVELOPMENT\\Repo_B\\forensic_suite_v2"
)

$residual = Get-ChildItem -Path $RepoRoot -Recurse -File | Where-Object {
    $_.Extension -in $AllowedExtensions
} | Where-Object {
    $full = $_.FullName
    -not ($SkipPathPatterns | Where-Object { $full -like "$_" })
} | Select-String -Pattern $ResidualPatterns

if ($residual) {
    Write-Warning "Residual old development paths still found:"
    $residual |
        Sort-Object Path, LineNumber |
        Format-Table Path, LineNumber, Line -AutoSize
    exit 2
}
else {
    Write-Host "[OK] No residual old development paths found." -ForegroundColor Green
    exit 0
}
