<#
.SYNOPSIS
    Reports or rewrites hardcoded paths inside Repo A after migration to F:\DEVELOPMENT.

.DESCRIPTION
    Use -Report to list all occurrences.
    Use -Apply to rewrite them to use $Global:PrimaryRoot, $Global:RepoB, $Global:Tools, $Global:Secrets.

.PARAMETER Report
    Show all matches without modifying files.

.PARAMETER Apply
    Rewrite files in place (creates .bak backup files).

.EXAMPLE
    .\Update-Paths.ps1 -Report

.EXAMPLE
    .\Update-Paths.ps1 -Apply
#>

param(
    [switch]$Report,
    [switch]$Apply
)

if (-not ($Report -or $Apply)) {
    throw "Specify -Report or -Apply."
}

$RepoRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"

# Old patterns to replace
$oldPatterns = @(
    "C:\\development\\forensic_tracer_installer_project_root",
    "C:\\development\\forensic_suite_v2",
    "C:\\tools",
    "C:\\forensic_secrets",
    "F:/DEVELOPMENT/Repo_A/forensic_tracer_installer_project_root",
    "F:/DEVELOPMENT/Repo_B/forensic_suite_v2",
    "F:/tools",
    "F:/forensic_secrets"
)

# New variable-based replacements
$replacements = @{
    "C:\\development\\forensic_tracer_installer_project_root" = '$Global:PrimaryRoot'
    "C:\\development\\forensic_suite_v2"                     = '$Global:RepoB'
    "C:\\tools"                                              = '$Global:Tools'
    "C:\\forensic_secrets"                                   = '$Global:Secrets'
    "F:/DEVELOPMENT/Repo_A/forensic_tracer_installer_project_root"  = '$Global:PrimaryRoot'
    "F:/DEVELOPMENT/Repo_B/forensic_suite_v2"                       = '$Global:RepoB'
    "F:/tools"                                               = '$Global:Tools'
    "F:/forensic_secrets"                                    = '$Global:Secrets'
}

Write-Host "=== Scanning Repo A for hardcoded paths ===" -ForegroundColor Cyan

$files = Get-ChildItem $RepoRoot -Recurse -File |
    Where-Object { $_.Extension -in '.ps1','.psm1','.psd1','.py','.cmd','.bat','.iss','.json','.yaml','.yml','.cfg','.txt' } |
    Where-Object { $_.FullName -notmatch "backup|_temp_installed|dist|build|installer_payload" }

$results = @()

foreach ($file in $files) {
    $matches = Select-String -Path $file.FullName -Pattern $oldPatterns -SimpleMatch
    if ($matches) {
        foreach ($m in $matches) {
            $results += [pscustomobject]@{
                File = $file.FullName
                Line = $m.LineNumber
                Text = $m.Line.Trim()
            }
        }
    }
}

if ($Report) {
    Write-Host "`n=== REPORT MODE ===" -ForegroundColor Yellow
    $results | Sort-Object File, Line | Format-Table -AutoSize
    Write-Host "`nFound $($results.Count) occurrences."
    return
}

if ($Apply) {
    Write-Host "`n=== APPLY MODE ===" -ForegroundColor Yellow
    foreach ($file in $results.File | Select-Object -Unique) {
        $content = Get-Content $file -Raw
        $backup  = "$file.bak"
        Copy-Item $file $backup -Force

        foreach ($old in $oldPatterns) {
            if ($content -match [regex]::Escape($old)) {
                $content = $content -replace [regex]::Escape($old), $replacements[$old]
            }
        }

        Set-Content $file $content -Encoding UTF8
        Write-Host "[UPDATED] $file" -ForegroundColor Green
    }

    Write-Host "`nAll replacements applied. Backup files (.bak) created." -ForegroundColor Green
}
