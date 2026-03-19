# Final Authoritative Folder Tree — Forensic Suite V9.3.3 (After Installation)

This document defines the final, authoritative folder tree on a target machine immediately after installing the Forensic Suite V9.3.3 runtime.

---

## 1. Root Folder

```
C:\forensic_suite_v2\
```

If blue/green deployment is used:

```
C:\forensic_suite_v2_green\
C:\forensic_suite_v2_blue\
C:\forensic_suite_v2  → symlink to active slot
```

---

## 2. Final Folder Tree

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

This is the **only** valid structure.

---

## 3. Files That Must Never Appear

The following are forbidden on a deployed host:

- Source code  
- Development scripts  
- Tests  
- Documentation  
- Build artifacts  
- Installer payload  
- Python caches  
- Grafana dashboards  
- Indexers  

The Combined Validator enforces this.

---

## 4. Runtime Guarantees

- Deterministic runtime environment  
- No drift between hosts  
- Wheel is the authoritative codebase  
- Scripts are runtime‑only  
- Environment templates are consistent  
- Blue/green switching is safe and atomic  

---

## 5. Summary

The target machine contains a **strict, minimal runtime mirror** of the suite. All development‑time files remain in Repo A and never propagate to deployed hosts.

---
