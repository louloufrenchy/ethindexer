# Sync‑DevTrees Pipeline — Forensic Suite V9.3.3

This document describes the Sync‑Dev pipeline used to rebuild Repo B (runtime mirror) from Repo A (development workspace) in a deterministic and validated manner.

---

## 1. Purpose

Sync‑Dev ensures:

- Repo B always matches the wheel‑based runtime model  
- No development files leak into Repo B  
- Runtime scripts and wheel artifacts are always up‑to‑date  
- The environment is reproducible across machines  

---

## 2. Pipeline Overview

```
Sync‑DevTrees.FullSuite.ps1
    → Invoke‑Preflight
    → DryRun
    → Apply
    → RepoB Validation
```

---

## 3. Stages

### **3.1 Preflight**
Runs the Combined Validator:

- Repo A validated (relaxed)
- Repo B validated (strict)

Sync‑Dev stops immediately if Preflight fails.

---

### **3.2 DryRun**
Shows:

- Files to be added to Repo B  
- Files to be removed  
- Files to be updated  

No changes are made.

---

### **3.3 Apply**
Rebuilds Repo B:

- Clears invalid files  
- Copies wheel and runtime scripts  
- Copies bootstrap and templates  
- Ensures strict runtime‑only structure  

---

### **3.4 Post‑Apply Validation**
Runs strict Repo B validation to confirm:

- No dev files leaked  
- All required runtime files exist  
- Wheel and scripts are consistent  

---

## 4. Repo B Structure After Sync‑Dev

```
scripts/
wheel/
bootstrap.ps1
env.template.json
dot_env.template
```

No other files are permitted.

---

## 5. Deterministic Behavior

- Sync‑Dev always produces the same Repo B for the same Repo A  
- No drift  
- No partial state  
- No legacy exclusions or mapping CSVs  

---

## 6. Summary Diagram

```
Repo A (Dev Workspace)
        │
        ▼
Invoke‑Preflight
        │
        ▼
DryRun ──► Apply ──► RepoB Validation
        │
        ▼
Repo B (Strict Runtime Mirror)
```

---
