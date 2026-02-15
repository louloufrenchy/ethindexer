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

[Files]
Source: "installer_payload\*"; DestDir: "{app}"; Flags: recursesubdirs

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
