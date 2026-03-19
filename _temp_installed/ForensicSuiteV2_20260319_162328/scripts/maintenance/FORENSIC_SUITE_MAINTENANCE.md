$patterns = @(
    "C:\\development",
    "C:/development",
    "forensic_tracer_installer_project_root",
    "forensic_suite_v2"
)

Get-ChildItem $root -Recurse -File |
    Where-Object { $_.Extension -in '.ps1','.psm1','.psd1','.py','.cmd','.bat','.iss','.json','.yaml','.yml','.cfg','.txt' } |
    Select-String -Pattern $patterns |
    Sort-Object Path,LineNumber |
    Format-Table Path, LineNumber, Line -AutoSize

⭐ Only these scripts need to be opened and updated

🟩 1. Repo A – Installer / Build / Deploy Scripts (critical)
These are the ones that must be updated to use:

Code
$Global:PrimaryRoot = "F:\DEVELOPMENT\Repo_A\forensic_tracer_installer_project_root"
$Global:RepoB       = "F:\DEVELOPMENT\Repo_B\forensic_suite_v2"
$Global:Tools       = "F:\tools"
$Global:Secrets     = "F:\forensic_secrets"
Update these:
A. Build & Installer Pipeline
scripts\build_pyinstaller.ps1

scripts\build_installer.ps1

scripts\build_wheel.ps1

scripts\install_forensic_suite.ps1

scripts\refresh_installer_payload.ps1

scripts\repair_installer_payload.ps1

scripts\validate_installer_payload.ps1

B. Deployment / Orchestration
scripts\Invoke-ForensicRelease.ps1

scripts\Invoke-Preflight.ps1

scripts\post_deploy_healthcheck.ps1

scripts\orchestrator\Invoke-ForensicDeployment.ps1

scripts\orchestrator\Rollback.ps1

scripts\orchestrator\Deploy-ForensicSuite.psm1

scripts\orchestrator\deployment_manifest.json  
(contains absolute paths)

C. Dev Sync Tools
scripts\Sync-DevTrees.Apply.ps1

scripts\Sync-DevTrees.DryRun.ps1

scripts\Sync-DevTrees.FullSuite.ps1

scripts\Sync-DevTrees.Rollback.ps1

scripts\Sync-DevTrees.Validate.ps1

scripts\Repair-Workspace.ps1

D. Repo Validators
scripts\forensic_suite_RepoA_validator_v2.ps1

scripts\forensic_suite_RepoB_validator.ps1

scripts\forensic_suite_RepoB_cleanup.ps1

scripts\forensic_suite_repo_mapping.ps1

E. Runtime Prep / Health
scripts\post_install_validation.ps1

scripts\test_install.ps1

scripts\validation\Test-ForensicRuntime.ps1

🟩 2. Repo B – Runtime Scripts (only a few matter)
Most of Repo B is runtime code and does not need updates.

Only update these if they contain absolute paths:

Likely to contain hardcoded paths:
forensic_suite_v2\scripts\install_services.ps1

forensic_suite_v2\scripts\windows_orchestrator_service.ps1

forensic_suite_v2\scripts\healthcheck.ps1

forensic_suite_v2\scripts\healthcheck_core.ps1

forensic_suite_v2\tools\loadforensicenv.ps1

These often reference:

Code
C:\forensic_suite_v2
C:\forensic_suite_logs
C:\forensic_state
You may want to parameterize these later, but they are runtime paths, not dev paths.

🟩 3. Ignore everything under:
❌ backup_forensic_suite_v2_*
These are old backups — do not modify.

❌ _temp_installed\ForensicSuiteV2_*
These are temporary installer extraction folders — ignore.

❌ dist\
Wheel and tarball outputs — ignore.

❌ build\ForensicSuite\
PyInstaller output — ignore.

❌ installer_payload\forensic_suite_v2\...
This is a copy of Repo B used for packaging.
It will be overwritten by refresh_installer_payload.ps1.

So you never update files inside installer_payload manually.

🟩 4. The authoritative list (final)
Here is the exact list of scripts you must open and update:

Code
scripts\build_pyinstaller.ps1
scripts\build_installer.ps1
scripts\build_wheel.ps1
scripts\install_forensic_suite.ps1
scripts\refresh_installer_payload.ps1
scripts\repair_installer_payload.ps1
scripts\validate_installer_payload.ps1

scripts\Invoke-ForensicRelease.ps1
scripts\Invoke-Preflight.ps1
scripts\post_deploy_healthcheck.ps1

scripts\orchestrator\Invoke-ForensicDeployment.psm1
scripts\orchestrator\Deploy-ForensicSuite.psm1
scripts\orchestrator\Rollback.ps1
scripts\orchestrator\deployment_manifest.json

scripts\Sync-DevTrees.Apply.ps1
scripts\Sync-DevTrees.DryRun.ps1
scripts\Sync-DevTrees.FullSuite.ps1
scripts\Sync-DevTrees.Rollback.ps1
scripts\Sync-DevTrees.Validate.ps1
scripts\Repair-Workspace.ps1

scripts\forensic_suite_RepoA_validator_v2.ps1
scripts\forensic_suite_RepoB_validator.ps1
scripts\forensic_suite_RepoB_cleanup.ps1
scripts\forensic_suite_repo_mapping.ps1

scripts\post_install_validation.ps1
scripts\test_install.ps1
scripts\validation\Test-ForensicRuntime.ps1
And optionally:

Code
forensic_suite_v2\scripts\install_services.ps1
forensic_suite_v2\scripts\windows_orchestrator_service.ps1
forensic_suite_v2\tools\loadforensicenv.ps1


