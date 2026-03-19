# Authoritative Deployment Tree — Forensic Suite V9.3.3 (Target Machine)

This document defines the authoritative folder structure on a target machine after deploying the Forensic Suite V9.3.3 installer. It reflects the wheel‑based runtime model and strict runtime‑only structure.

---

## 1. Deployment Root

The suite installs under:

```
C:\forensic_suite_v2\
```

A blue/green slot may be used:

```
C:\forensic_suite_v2_green\
C:\forensic_suite_v2_blue\
```

A symlink points to the active slot:

```
C:\forensic_suite_v2  →  C:\forensic_suite_v2_green
```

---

## 2. Authoritative Runtime Structure

```
C:\forensic_suite_v2\
│
├── wheel\
│     └── forensic_suite_v2‑<version>.whl
│
├── scripts\
│     ├── start_services.ps1
│     ├── stop_services.ps1
│     ├── configure_env.ps1
│     └── runtime_helpers.ps1
│
├── bootstrap.ps1
├── env.template.json
└── dot_env.template
```

---

## 3. What Must NOT Exist

The following must never appear on a target machine:

- Source tree (`forensic_suite_v2/`)
- Development scripts
- Tests
- Grafana dashboards
- Indexers
- Documentation
- Build artifacts (`dist/`, `Output/`)
- Installer payload
- Python caches

The Combined Validator enforces this.

---

## 4. Deployment Guarantees

- Only runtime artifacts are deployed  
- No development files leak  
- Wheel is the single source of truth  
- Scripts are runtime‑only  
- Environment templates are consistent  
- Blue/green switching is safe  

---

## 5. Summary

The target machine contains a **strict, minimal, runtime‑only** version of the suite. All development‑time files remain in Repo A and never propagate to deployed hosts.

---
