# 📚 Forensic Suite V9.3.3 — Architecture & Pipeline Documentation

This directory contains the authoritative documentation for the Forensic Suite V9.3.3 development and deployment pipeline. These documents describe the full validation model, Sync‑Dev pipeline, build process, and deployment flow.

All documents in this folder are **safe to store in Repo A**.  
They do **not** participate in Sync‑Dev and will **never** sync or contaminate Repo B.

---

## 📘 Validation & Pipeline Map  
**File:** `ForensicSuite_Validation_and_Pipeline_Map.md`  
A complete written overview of the entire V9.3.3 architecture, including:

- Relaxed Repo A model (full development workspace)  
- Strict Repo B model (runtime‑only wheel mirror)  
- Combined Validator behavior  
- Preflight gating  
- Sync‑Dev pipeline  
- BuildSuiteSafe and BuildSuite flows  
- Deployment preflight and deployment flows  
- A full command‑to‑validator dependency table  

This is the **master reference document** for understanding how the suite works end‑to‑end.

---

## 🧩 Mermaid Pipeline Diagram  
**File:** `ForensicSuite_Pipeline_MermaidDiagram.md`  
A rendered Mermaid diagram showing the complete pipeline visually:

- Validation flow  
- Cleanup flow  
- Sync‑Dev flow  
- Build flow  
- Deployment flow  
- Repair‑Workspace flow  

Ideal for GitHub rendering, architecture reviews, and onboarding.

---

## 🖥️ ASCII Flowchart  
**File:** `ForensicSuite_Pipeline_ASCII_Flowchart.txt`  
A terminal‑friendly ASCII diagram of the entire pipeline:

- Perfect for console environments  
- Easy to paste into logs, terminals, or chat  
- Mirrors the Mermaid diagram exactly  

Useful for quick reference during development or troubleshooting.

---

## 📁 Storage Location  
All documentation files live under:

```
RepoA_root\Documents\
```

This location is **safe**, because:

- Repo A is allowed to contain any development‑time files  
- Sync‑Dev only mirrors runtime‑only artifacts into Repo B  
- Documentation never syncs to Repo B  
- The Combined Validator does not inspect or restrict documentation folders  

This ensures documentation never interferes with the build, validation, or deployment pipeline.

---
