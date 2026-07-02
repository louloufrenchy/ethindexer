# ============================================================
#  Windows Server 2025 Deterministic rsync Bootstrap
#  Fully automated provisioning for Louis' forensic VMs
# ============================================================

$ErrorActionPreference = "Stop"

Write-Host "[+] Starting deterministic rsync bootstrap..."

# --- Create tools directory ---------------------------------------------------
if (!(Test-Path "C:\tools")) {
    New-Item -ItemType Directory -Path "C:\tools" | Out-Null
}
Write-Host "[+] Using C:\tools"

# --- Install 7-Zip ------------------------------------------------------------
$SevenZipInstaller = "C:\tools\7zip.exe"
if (!(Test-Path $SevenZipInstaller)) {
    Write-Host "[+] Downloading 7-Zip..."
    Invoke-WebRequest -Uri "https://www.7-zip.org/a/7z2408-x64.exe" -OutFile $SevenZipInstaller
}

Write-Host "[+] Installing 7-Zip..."
Start-Process $SevenZipInstaller -ArgumentList "/S" -Wait

$SevenZipExe = "C:\Program Files\7-Zip\7z.exe"
if (!(Test-Path $SevenZipExe)) {
    throw "[-] 7-Zip installation failed."
}

# --- Download MSYS2 base ------------------------------------------------------
$MSYSXZ = "C:\tools\msys2.tar.xz"
if (!(Test-Path $MSYSXZ)) {
    Write-Host "[+] Downloading MSYS2 base..."
    Invoke-WebRequest -Uri "https://repo.msys2.org/distrib/msys2-x86_64-latest.tar.xz" -OutFile $MSYSXZ
}

Write-Host "[+] Extracting MSYS2..."
& $SevenZipExe x $MSYSXZ -o"C:\tools\msys2"
& $SevenZipExe x "C:\tools\msys2\msys2.tar" -o"C:\tools\msys2"

$MSYSROOT = "C:\tools\msys2\msys64"
if (!(Test-Path $MSYSROOT)) {
    throw "[-] MSYS2 extraction failed."
}

Write-Host "[+] MSYS2 extracted."

# --- Download rsync packages --------------------------------------------------
Write-Host "[+] Downloading rsync packages..."

$Packages = @{
    "rsync.pkg.tar.zst"    = "https://repo.msys2.org/msys/x86_64/rsync-3.3.0-1-x86_64.pkg.tar.zst"
    "libxxhash.pkg.tar.zst" = "https://repo.msys2.org/msys/x86_64/libxxhash-0.8.2-1-x86_64.pkg.tar.zst"
    "libzstd.pkg.tar.zst"   = "https://repo.msys2.org/msys/x86_64/libzstd-1.5.6-1-x86_64.pkg.tar.zst"
}

foreach ($pkg in $Packages.Keys) {
    $OutFile = "C:\tools\$pkg"
    if (!(Test-Path $OutFile)) {
        Write-Host "[+] Downloading $pkg..."
        Invoke-WebRequest -Uri $Packages[$pkg] -OutFile $OutFile
    }
}

# --- Define Git root ----------------------------------------------------------
$GitRoot = "C:\Program Files\Git"
if (!(Test-Path $GitRoot)) {
    throw "[-] Git for Windows not found."
}

# --- Extract outer .zst packages ----------------------------------------------
Write-Host "[+] Extracting outer .zst packages..."
foreach ($pkg in $Packages.Keys) {
    & $SevenZipExe x "C:\tools\$pkg" -o"$GitRoot"
}

# --- Extract inner .tar packages ----------------------------------------------
Write-Host "[+] Extracting inner .tar packages..."
$TarFiles = Get-ChildItem "$GitRoot" -Filter "*.tar" -Recurse
foreach ($tar in $TarFiles) {
    & $SevenZipExe x $tar.FullName -o"$GitRoot"
}

Write-Host "[+] rsync installed."

# --- Deploy deterministic .bashrc ---------------------------------------------
Write-Host "[+] Deploying deterministic .bashrc..."

$Bashrc = @'
# ---------------------------------------------------------
# Louis' deterministic Git Bash profile for Windows Server
# ---------------------------------------------------------

alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias rs='rsync -av --progress'

export PATH="/c/Program Files/Git/usr/bin:/c/Program Files/Git/bin:/c/Program Files/Git/cmd:/c/tools/msys2/msys64/usr/bin:$PATH"
export MSYS2_PATH_TYPE=inherit

alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
'@

Set-Content -Path "$env:USERPROFILE\.bashrc" -Value $Bashrc -Encoding UTF8

Write-Host "[+] .bashrc deployed."

# --- Validation ---------------------------------------------------------------
Write-Host "[+] Validating rsync installation..."

$RsyncPath = "C:\Program Files\Git\usr\bin\rsync.exe"
if (Test-Path $RsyncPath) {
    Write-Host "[PASS] rsync.exe found at: $RsyncPath"
} else {
    Write-Host "[FAIL] rsync.exe missing."
}

Write-Host "[+] Bootstrap complete."
Write-Host "[+] Open Git Bash and run: rsync --version"
