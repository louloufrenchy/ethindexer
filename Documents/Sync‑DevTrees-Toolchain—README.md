# Sync‑DevTrees Toolchain — Forensic Suite V9.3.3

This document describes the Sync‑Dev toolchain used to maintain a deterministic, validated runtime mirror (Repo B) from the development workspace (Repo A). It reflects the modern V9.3.3 architecture, including the Combined Validator, Preflight, and wheel‑based runtime model.

---

## 1. Purpose of the Toolchain

The Sync‑Dev toolchain ensures:

- Repo B always matches the strict runtime‑only structure  
- No development files leak into Repo B  
- Runtime scripts and wheel artifacts are always up‑to‑date  
- The environment is reproducible across machines  
- Validation gates prevent drift or partial state  

Repo A is flexible. Repo B is strict.

---

## 2. Components of the Toolchain

### **2.1 Combined Validator**
The authoritative validator for both repos:

```
scripts/forensic_suite_Combined_validator.ps1
```

Validates:

- Repo A (relaxed rules)
- Repo B (strict runtime rules)

Used by all Sync‑Dev operations.

---

### **2.2 Preflight**
Universal gatekeeper:

```
scripts/Invoke‑Preflight.ps1
```

Ensures both repos are valid before any Sync‑Dev operation.

---

### **2.3 Repo B Cleanup**
Deterministic reset:

```
scripts/forensic_suite_RepoB_cleanup.ps1
```

Deletes all contents of Repo B and recreates the runtime‑only structure.

---

### **2.4 Sync‑Dev FullSuite**
The orchestrator:

```
scripts/Sync‑DevTrees.FullSuite.ps1
```

Runs:

- Preflight  
- DryRun  
- Apply  
- Post‑Apply Validation  

---

### **2.5 DryRun**
Shows:

- Files to be added  
- Files to be removed  
- Files to be updated  

No changes are made.

---

### **2.6 Apply**
Rebuilds Repo B:

- Copies wheel  
- Copies runtime scripts  
- Copies bootstrap and templates  
- Enforces strict runtime‑only structure  

---

### **2.7 Post‑Apply Validation**
Ensures Repo B is:

- Clean  
- Strict  
- Free of dev files  
- Fully consistent with the wheel  

---

## 3. Repo B Structure After Sync‑Dev

```
scripts/
wheel/
bootstrap.ps1
env.template.json
dot_env.template
```

Nothing else is permitted.

---

## 4. Deterministic Behavior

The toolchain guarantees:

- Same Repo B for the same Repo A  
- No drift  
- No partial state  
- No legacy exclusions or mapping CSVs  
- No nested suite issues  

---

## 5. Summary Flow

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
