# Confirming That Files Are Updated After a New Build and Redeployment  
_Forensic Suite V9.3.3 — Deterministic Validation Guide_

This document describes how to confirm that a new build and redeployment of the Forensic Suite V9.3.3 has successfully updated all runtime files across the environment. It reflects the modern wheel‑based runtime model, strict Repo B validation, and deterministic deployment pipeline.

---

## 1. Overview

A successful build and redeployment must ensure:

- The **wheel** is updated to the new version.
- The **PyInstaller bundle** is rebuilt.
- The **installer payload** is refreshed.
- The **installer EXE** is rebuilt.
- The **deployment target** receives the updated runtime files.
- No stale or legacy files remain on the target machine.
- Repo B reflects the new runtime state.
- The active blue/green slot contains the updated artifacts.

The V9.3.3 pipeline guarantees determinism, but verification steps remain essential for operational confidence.

---

## 2. Confirming the Build Output

After running:

```
Invoke‑BuildSuiteSafe
```

verify the following in Repo A:

### **2.1 Wheel**
Check:

```
dist/forensic_suite_v2‑<version>.whl
```

Confirm:

- Version number incremented.
- Timestamp matches the build time.

### **2.2 PyInstaller Bundle**
Check:

```
Output/forensic_suite_v2/
```

Confirm:

- Executable timestamps match the build.
- No stale files remain.

### **2.3 Installer Payload**
Check:

```
installer_payload/
```

Confirm:

- Wheel copied into payload.
- Runtime scripts updated.
- Templates updated.
- No development files present.

### **2.4 Installer EXE**
Check:

```
Output/installer/ForensicSuiteInstaller.exe
```

Confirm:

- Timestamp matches build.
- Size changed if code changed.
- Digital signature (if used) is valid.

---

## 3. Confirming Repo B After Sync‑Dev

After running:

```
Update‑ForensicSuiteDev -Apply
```

or after `Repair‑Workspace`, verify Repo B:

### **3.1 Repo B Structure**
Repo B must contain only:

```
scripts/
wheel/
bootstrap.ps1
env.template.json
dot_env.template
```

### **3.2 Wheel Version**
Check:

```
RepoB_root/wheel/forensic_suite_v2‑<version>.whl
```

Confirm it matches the newly built wheel.

### **3.3 Runtime Scripts**
Check timestamps in:

```
RepoB_root/scripts/
```

They must match the updated payload.

### **3.4 Strict Validation**
Run:

```
Test‑ForensicSuiteAll
```

Expect exit code `0`.

---

## 4. Confirming Deployment Preflight

Before deploying, run:

```
Invoke‑DeployPreflight
```

This validates:

- Payload integrity.
- Installer EXE presence.
- Deployment scripts.
- Wheel version consistency.

Deployment must not proceed unless Preflight returns `0`.

---

## 5. Confirming the Target Machine After Deployment

After running:

```
Invoke‑DeployHost
```

or:

```
Invoke‑DeployCluster
```

verify the target machine.

### **5.1 Active Slot**
Check the symlink:

```
C:\forensic_suite_v2  →  C:\forensic_suite_v2_green
```

or:

```
C:\forensic_suite_v2  →  C:\forensic_suite_v2_blue
```

### **5.2 Runtime Folder Structure**
The active slot must contain:

```
wheel/
scripts/
bootstrap.ps1
env.template.json
dot_env.template
```

### **5.3 Wheel Version**
Check:

```
C:\forensic_suite_v2\wheel\forensic_suite_v2‑<version>.whl
```

It must match the newly built version.

### **5.4 Script Timestamps**
Check:

```
C:\forensic_suite_v2\scripts\
```

Timestamps must match the updated payload.

### **5.5 No Development Files**
Confirm the absence of:

- Source tree  
- Tests  
- Grafana dashboards  
- Indexers  
- Documentation  
- Build artifacts  
- Python caches  

The Combined Validator enforces this.

---

## 6. Confirming Service Behavior

If the suite includes services:

- Restart services using the updated scripts.
- Confirm logs reflect the new version.
- Confirm no errors related to missing or stale files.

---

## 7. Deterministic Validation Checklist

Use this checklist after every build + redeployment:

- [ ] Wheel version updated  
- [ ] PyInstaller bundle rebuilt  
- [ ] Installer payload refreshed  
- [ ] Installer EXE rebuilt  
- [ ] Repo B rebuilt via Sync‑Dev  
- [ ] Combined Validator returns `0`  
- [ ] DeployPreflight returns `0`  
- [ ] Target machine contains updated wheel  
- [ ] Target machine scripts updated  
- [ ] No dev files on target machine  
- [ ] Services running with updated code  

---

## 8. Summary

The V9.3.3 pipeline ensures deterministic, reproducible updates across development, build, and deployment environments. By validating the wheel, payload, Repo B, and target machine, you can confirm with certainty that the new build is fully deployed and no stale artifacts remain.

---
