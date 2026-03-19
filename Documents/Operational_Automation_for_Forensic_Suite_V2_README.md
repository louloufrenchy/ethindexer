# Operational Automation for Forensic Suite V9.3.3

This document describes the operational automation model for the Forensic Suite V9.3.3, including workspace repair, validation, Sync‑Dev, build, and deployment automation.

---

## 1. Automation Principles

The automation model is built on:

- Deterministic operations  
- Strict validation gates  
- Reproducible runtime mirrors  
- Clear separation of development (Repo A) and runtime (Repo B)  
- Wheel‑based runtime execution  
- Zero drift between environments  

---

## 2. Core Automation Scripts

### **2.1 Combined Validator**
The single source of truth for validation:

```
scripts/forensic_suite_Combined_validator.ps1
```

Validates:

- Repo A (relaxed)
- Repo B (strict)

Used by all major automation entrypoints.

---

### **2.2 Preflight**
Universal gatekeeper:

```
scripts/Invoke‑Preflight.ps1
```

No build, sync, or deployment proceeds unless Preflight passes.

---

### **2.3 Repo B Cleanup**
Deterministic runtime reset:

```
scripts/forensic_suite_RepoB_cleanup.ps1
```

Deletes all contents of Repo B and recreates the runtime‑only structure.

---

### **2.4 Sync‑Dev Pipeline**
Rebuilds Repo B from Repo A:

```
scripts/Sync‑DevTrees.FullSuite.ps1
scripts/Sync‑DevTrees.DryRun.ps1
scripts/Sync‑DevTrees.Apply.ps1
scripts/Sync‑DevTrees.Validate.ps1
```

---

### **2.5 Build Pipeline**
Produces wheel, PyInstaller bundle, payload, and installer EXE:

```
Invoke‑BuildSuiteSafe
Invoke‑BuildSuite
```

Includes:

- Preflight  
- Wheel build  
- PyInstaller build  
- Payload refresh  
- Installer EXE build  
- Post‑install validation  
- Payload integrity validation  

---

### **2.6 Deployment Pipeline**
Validates and deploys:

```
Invoke‑DeployPreflight
Invoke‑DeployHost
Invoke‑DeployCluster
```

Deployment always uses the validated installer payload.

---

## 3. Deterministic Recovery

```
Repair‑Workspace
    → Clear Repo B
    → Preflight
    → Sync‑Dev Apply
```

This guarantees a clean, reproducible workspace state at any time.

---

## 4. Operational Guarantees

- Repo A can contain any development‑time files  
- Repo B is always a strict runtime mirror  
- All operations pass through Preflight  
- All validation flows through the Combined Validator  
- No drift between build, test, and deployment environments  
- Documentation and non‑runtime files never sync to Repo B  

---

## 5. Summary

The V9.3.3 automation model is deterministic, modular, and safe. It ensures that:

- Development is flexible  
- Runtime is strict  
- Builds are reproducible  
- Deployments are validated  
- Recovery is always possible  

---
