# Forensic Suite V9.3.3 — End‑to‑End Deployment Pipeline

This document describes the complete deployment pipeline for the Forensic Suite V9.3.3, from development workspace to deployed runtime nodes. It reflects the modern wheel‑based architecture, strict runtime mirror, and deterministic validation model.

---

## 1. Development Workspace (Repo A)

Repo A is a full development workspace and may contain:

- Source tree (`forensic_suite_v2/`)
- Scripts (`scripts/`)
- Build artifacts (`dist/`, `Output/`)
- Installer payload (`installer_payload/`)
- Documentation (`Documents/`)
- Tests, dashboards, grafana, tools, notebooks, etc.

Repo A is validated using **relaxed rules**:
- Required anchors must exist (source tree, scripts, dist, installer_payload, Output, pyproject.toml)
- Everything else is allowed

---

## 2. Runtime Mirror (Repo B)

Repo B is a strict runtime‑only mirror containing:

```
scripts/
wheel/
bootstrap.ps1
env.template.json
dot_env.template
```

Repo B is validated using **strict rules**:
- Only runtime artifacts allowed
- No nested suite
- No grafana, dashboards, indexers, tests, or dev files

---

## 3. Preflight (Universal Gate)

All build, sync, and deployment operations pass through:

```
Invoke‑Preflight.ps1
    → forensic_suite_Combined_validator.ps1
```

Preflight ensures:

- Repo A is structurally valid (relaxed)
- Repo B is clean and runtime‑only (strict)

No operation proceeds unless Preflight returns exit code `0`.

---

## 4. Sync‑Dev Pipeline

The Sync‑Dev pipeline rebuilds Repo B deterministically:

1. **DryRun** — show planned changes  
2. **Apply** — rebuild Repo B from Repo A  
3. **Post‑Apply Validation** — strict runtime validation  

This ensures Repo B always matches the wheel‑based runtime model.

---

## 5. Build Pipeline

The build pipeline produces:

- Python wheel  
- PyInstaller bundle  
- Installer payload  
- Installer EXE  

Flow:

```
Invoke‑BuildSuiteSafe
    → Clear Repo B
    → Invoke‑BuildSuite
        → Preflight
        → Build wheel
        → Build PyInstaller bundle
        → Refresh installer payload
        → Build installer EXE
        → Post‑install validation
        → Payload integrity validation
```

---

## 6. Deployment Pipeline

Deployment uses the validated installer payload and EXE:

```
Invoke‑DeployPreflight
    → Validate payload integrity
    → Validate installer EXE
    → Validate deployment scripts
```

Then:

```
Invoke‑DeployHost
Invoke‑DeployCluster
```

Deployment is always performed from the **validated installer payload**, not from Repo A or Repo B.

---

## 7. Deterministic Recovery

```
Repair‑Workspace
    → Clear Repo B
    → Preflight
    → Sync‑Dev Apply
```

This guarantees a clean, reproducible workspace state.

---

## 8. Summary Diagram

```
Repo A (Dev Workspace)
        │
        ▼
Preflight (Combined Validator)
        │
        ├── Sync‑Dev → Repo B (Runtime Mirror)
        │
        └── BuildSuite → Wheel + EXE + Payload
                         │
                         ▼
                DeployPreflight
                         │
                         ▼
                DeployHost / DeployCluster
```

---
