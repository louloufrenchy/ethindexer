[Setup]
AppName=Forensic Suite v2
AppVersion=0.1.0
DefaultDirName={pf}\ForensicSuiteV2
DefaultGroupName=Forensic Suite v2
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputBaseFilename=ForensicSuiteV2-Setup
OutputDir=Output
ArchitecturesInstallIn64BitMode=x64
Compression=lzma
SolidCompression=yes

[Dirs]
Name: "C:\forensic_secrets"; Flags: uninsneveruninstall

[Files]
; Main application payload
Source: "installer_payload\*"; DestDir: "{app}"; Flags: recursesubdirs

; Template secrets (never real secrets)
Source: "env.template.json"; DestDir: "C:\forensic_secrets"; Flags: onlyifdoesntexist
Source: "dot_env.template"; DestDir: "C:\forensic_secrets"; DestName: ".env"; Flags: onlyifdoesntexist

[Run]
Filename: "powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -File ""{app}\bootstrap.ps1"""; \
  WorkingDir: "{app}"; \
  Flags: runascurrentuser waituntilterminated

[Icons]
Name: "{group}\Forensic Suite GUI"; \
  Filename: "{app}\gui\forensic_suite_v2_gui.bat"; \
  WorkingDir: "{app}"

Name: "{group}\Multi-Chain Dashboard"; \
  Filename: "powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -File ""{app}\dashboards\multi_chain_dashboard.ps1"""; \
  WorkingDir: "{app}"

Name: "{group}\Run All Indexers"; \
  Filename: "powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -File ""{app}\scripts\run_all_indexers.ps1"""; \
  WorkingDir: "{app}"
