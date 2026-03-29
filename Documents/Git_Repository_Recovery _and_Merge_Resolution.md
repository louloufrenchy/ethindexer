# Post‑Mortem: Git Repository Recovery & Merge Resolution  
**Project:** Repo_A / forensic_tracer_installer_project_root  
**Author:** Louis  
**Date:** 2026‑03‑20  

---

## 📌 Overview  
This post‑mortem documents the full recovery process after Repo_A became corrupted during a file‑based transfer to host 192.168.0.28.  
The root causes were:

- `.git/objects` corruption due to NTFS ACL inheritance issues  
- Missing write permissions inside `.git`  
- A robocopy transfer that excluded `.git`, leaving a working tree without Git metadata  
- Build artifacts (`_temp_installed`) accidentally tracked, causing 10,000+ merge conflicts  
- A large branch divergence between `master` and `dev`  

This document captures **every step**, **every command**, and the **final resolution**.

---

## 🧨 Root Cause Summary  
1. Repo_A was copied to host 28 using `robocopy` with `.git` excluded.  
2. The working tree on host 28 had **real code changes**, but **no Git metadata**.  
3. Attempting to re‑initialize Git exposed NTFS ACL corruption inside `.git/objects`.  
4. After fixing ACLs, Git was re‑initialized and reconnected to origin.  
5. A merge between `master` → `dev` produced **10,000+ conflicts** due to `_temp_installed` being tracked.  
6. Removing `_temp_installed` from Git resolved the noise, leaving only real conflicts.  
7. All conflicts were resolved, staged, and committed successfully.

---

## 🛠️ Step‑by‑Step Recovery

### 1. **Verify the working tree was not a Git repo**
```powershell
git status
# fatal: not a git repository
```

### 2. **Re‑initialize Git**
```powershell
git init
git remote add origin https://github.com/<repo>/Repo_A.git
git fetch origin
```

### 3. **Fix NTFS ACL corruption inside `.git/objects`**
```powershell
icacls .git /reset /t /c
icacls .git /grant:r "$($env:USERNAME):(OI)(CI)F" /t /c
```

### 4. **Reconnect to the correct branch**
```powershell
git checkout dev
```

### 5. **Compare working tree to origin**
```powershell
git status
```

### 6. **Stage all real changes**
```powershell
git add .
```

### 7. **Attempt merge (master → dev)**
```powershell
git merge master
```

This produced **10,000+ conflicts** due to `_temp_installed`.

---

## 🧹 Cleanup: Remove `_temp_installed` from Git

### 8. **Add folder to `.gitignore`**
```
_temp_installed/
temp_installed/
```

### 9. **Remove it from Git index (but keep on disk)**
```powershell
git rm -r --cached _temp_installed
```

### 10. **Commit the cleanup**
```powershell
git add .gitignore
git commit -m "Remove temp_installed artifacts from Git tracking"
```

This eliminated the 10k junk conflicts.

---

## 🔧 Resolve Real Merge Conflicts

### 11. **Open VS Code merge editor**
Resolved conflicts in:
- PowerShell orchestration scripts  
- Python indexer services  
- YAML configs  
- Installer payload scripts  

### 12. **Stage resolved files**
```powershell
git add <file>
# or
git add .
```

### 13. **Verify merge state**
```powershell
git status
# All conflicts fixed but you are still merging.
```

### 14. **Commit the merge**
Git opened `.git/COMMIT_EDITMSG`:

```
Merge branch 'master' into dev
```

Save + close editor.

Terminal output:
```
[dev 8f8bc9c] Merge branch 'master' into dev
```

---

## 🚀 Finalization

### 15. **Push merged branch**
```powershell
git push origin dev
```

### 16. **Verify clean working tree**
```powershell
git status
# nothing to commit, working tree clean
```

---

## 🧭 Lessons Learned

### ✔ Never use `robocopy` to transfer Git repos  
It strips `.git` and breaks metadata.

### ✔ Always exclude build artifacts  
`_temp_installed` must never be tracked.

### ✔ NTFS ACL corruption can silently break Git  
Resetting ACLs restored `.git/objects` functionality.

### ✔ Large merges require a clean working tree  
Removing junk artifacts made the merge manageable.

### ✔ VS Code merge editor is essential  
Only real conflicts remained after cleanup.

---

## 🏁 Final State  
- Repo fully repaired  
- `dev` branch merged cleanly with `master`  
- No ACL issues  
- No tracked build artifacts  
- Working tree clean  
- Ready for further development and debugging (`runtime-debug` branch)

---

## 📎 Appendix: Useful Commands

### Reset ACLs
```powershell
icacls .git /reset /t /c
icacls .git /grant:r "$($env:USERNAME):(OI)(CI)F" /t /c
```

### Remove tracked folder but keep it locally
```powershell
git rm -r --cached <folder>
```

### Extract file from another branch without overwriting
```powershell
git show master:scripts/Invoke-ForensicRelease.ps1 > Invoke-ForensicRelease.MASTER.ps1
```

### Create a scratch branch for debugging
```powershell
git switch -c runtime-debug
```

---

# ✅ End of Post‑Mortem
