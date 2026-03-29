# CHANGELOG — Transition from February 2026 Architecture to V9.3.3 Deterministic Model  
_Forensic Suite Development & Deployment Evolution_

This changelog documents the architectural, operational, and validation changes made between the **February 2026 toolchain** and the modern **V9.3.3 deterministic model**. It captures the shift from a loosely structured, partially manual workflow to a fully validated, reproducible, wheel‑based runtime system with strict runtime mirroring and relaxed development‑time flexibility.

---

## 1. Architectural Evolution

### February 2026 Model
- Mixed development/runtime structure.
- RepoA and RepoB both contained overlapping sets of files.
- Runtime behavior depended on source‑tree execution.
- No strict separation between dev‑time and runtime artifacts.
- Deployment relied on copying large folder trees.
- No single authoritative validator.

### V9.3.3 Deterministic Model
- RepoA is a **full development workspace** (relaxed rules).
- RepoB is a **strict runtime‑only mirror** (wheel‑based).
- Runtime execution is **wheel‑driven**, not source‑tree‑driven.
- Deployment uses a **validated installer payload** and EXE.
- All operations gated by a **single Combined Validator**.
- Full determinism: same inputs → same outputs → same deployment.

---

## 2. Validation Model Changes

### February 2026 Model
- Multiple validators with inconsistent rules.
- Manual checks required for RepoA and RepoB.
- No unified exit‑code model.
- No strict enforcement of runtime‑only structure.

### V9.3.3 Deterministic Model
- **Combined Validator** is the single source of truth.
- RepoA validated with **relaxed rules**.
- RepoB validated with **strict runtime‑only rules**.
- All major commands call the validator through **Preflight**.
- Clear exit codes for CI/CD and automation.

---

## 3. Sync‑Dev Pipeline Changes

### February 2026 Model
- Sync‑Dev relied on mapping CSVs and exclusion lists.
- RepoB often accumulated stale or dev‑time files.
- No deterministic cleanup.
- No post‑apply validation.

### V9.3.3 Deterministic Model
- Sync‑Dev is now a **four‑stage deterministic pipeline**:
  1. Preflight  
  2. DryRun  
  3. Apply  
  4. Post‑Apply Validation  
- RepoB is rebuilt from scratch using runtime‑only artifacts.
- No exclusions, no mapping CSVs, no legacy logic.
- Guaranteed reproducibility across machines.

---

## 4. Build Pipeline Changes

### February 2026 Model
- Build artifacts were inconsistent across runs.
- Installer payload was manually curated.
- PyInstaller bundle and wheel were not validated post‑build.
- No payload integrity validation.

### V9.3.3 Deterministic Model
- **Invoke‑BuildSuiteSafe** enforces:
  - RepoB cleanup  
  - Preflight  
  - Wheel build  
  - PyInstaller build  
  - Payload refresh  
  - Installer EXE build  
  - Post‑install validation  
  - Payload integrity validation  
- Build outputs are deterministic and validated.

---

## 5. Deployment Pipeline Changes

### February 2026 Model
- Deployment copied mixed dev/runtime folders.
- No validation of installer payload.
- No validation of installer EXE.
- No blue/green slot awareness.

### V9.3.3 Deterministic Model
- Deployment uses:
  - Validated installer payload  
  - Validated installer EXE  
  - Validated deployment scripts  
- **Invoke‑DeployPreflight** ensures deployment safety.
- Blue/green deployment supported with symlink switching.
- Target machine contains only strict runtime artifacts.

---

## 6. Repo A and Repo B Separation

### February 2026 Model
- RepoA and RepoB often drifted.
- RepoB contained dev‑time files.
- RepoA required manual cleanup.

### V9.3.3 Deterministic Model
- RepoA is **relaxed**: can contain docs, tests, dashboards, tools.
- RepoB is **strict**: runtime‑only, validated after every Sync‑Dev.
- Drift is impossible due to deterministic rebuilds.
- Documentation in `Documents/` is safe and never syncs.

---

## 7. Deterministic Recovery

### February 2026 Model
- Recovery required manual cleanup and manual copying.
- No guaranteed clean state.

### V9.3.3 Deterministic Model
- **Repair‑Workspace** provides a guaranteed clean recovery:
  - Clear RepoB  
  - Preflight  
  - Sync‑Dev Apply  
- Always returns workspace to a known‑good state.

---

## 8. Documentation Overhaul

### February 2026 Model
- Documentation reflected legacy assumptions:
  - Source‑tree runtime execution  
  - Mixed dev/runtime folders  
  - Manual deployment  
  - No unified validation model  

### V9.3.3 Deterministic Model
- All documentation updated to reflect:
  - Wheel‑based runtime  
  - Strict runtime mirror  
  - Combined Validator  
  - Preflight gating  
  - Deterministic Sync‑Dev  
  - Deterministic BuildSuiteSafe  
  - Validated deployment  
  - Blue/green slot model  
- Outdated February 2026 documents replaced with modern equivalents.

---

## 9. Summary of Key Improvements

- **Unified validation** across all operations.  
- **Deterministic builds** with validated payloads.  
- **Strict runtime mirror** ensures clean deployments.  
- **Relaxed development workspace** improves developer velocity.  
- **No drift** between environments.  
- **Full reproducibility** across machines.  
- **Clear documentation** aligned with the modern architecture.  

---

## 10. Final Notes

The transition from the February 2026 architecture to the V9.3.3 deterministic model represents a complete modernization of the Forensic Suite’s development, build, validation, and deployment workflows. The suite is now:

- More reliable  
- More predictable  
- Easier to maintain  
- Easier to validate  
- Fully reproducible  
- Safer to deploy  

This changelog should be kept alongside the updated documentation set to provide historical context for future maintainers.

---
