# forensic_suite_v2/core/trace_engine.py

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from forensic_suite_v2.core.plugin_loader import discover_plugins
from forensic_suite_v2.core.fs_logging import get_logger


log = get_logger("trace_engine")


# ------------------------------------------------------------
# Data structures
# ------------------------------------------------------------
@dataclass
class TraceSeed:
    chain: str
    kind: str          # "address", "tx", "utxo", etc.
    value: str
    max_depth: int = 3
    max_branches: int = 20


@dataclass
class TraceManifestV2:
    name: str
    created_at: str
    seeds: List[TraceSeed]
    options: Dict[str, Any]


# ------------------------------------------------------------
# Core helpers
# ------------------------------------------------------------
def _ensure_output_root(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def _manifest_output_dir(output_root: Path, manifest: TraceManifestV2) -> Path:
    safe_name = manifest.name.replace(" ", "_")
    return output_root / safe_name


async def _run_single_seed(
    plugins: Dict[str, Any],
    seed: TraceSeed,
    output_dir: Path,
    debug: bool = False,
) -> Dict[str, Any]:
    chain = seed.chain.lower()
    if chain not in plugins:
        raise ValueError(f"No plugin registered for chain '{chain}'")

    plugin = plugins[chain]

    if debug:
        log.info(
            "Running trace seed",
            extra={
                "chain": chain,
                "kind": seed.kind,
                "value": seed.value,
                "max_depth": seed.max_depth,
                "max_branches": seed.max_branches,
            },
        )

    # Plugin is responsible for honoring depth/branch limits
    result = plugin.trace(
        target={
            "kind": seed.kind,
            "value": seed.value,
            "max_depth": seed.max_depth,
            "max_branches": seed.max_branches,
        }
    )

    # Persist result as JSON
    output_dir.mkdir(parents=True, exist_ok=True)
    out_file = output_dir / f"{chain}_{seed.kind}_{seed.value[:16]}.json"
    with out_file.open("w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, default=str)

    return {
        "seed": asdict(seed),
        "output_file": str(out_file),
        "result_summary": getattr(result, "summary", None),
    }


# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------
async def run_multi_chain_trace_v2_async(
    manifest: TraceManifestV2,
    output_root: str | Path,
    debug: bool = False,
) -> Dict[str, Any]:
    """
    Run all seeds in a manifest, possibly across multiple chains.
    """
    plugins = discover_plugins()
    if debug:
        log.info(
            "Loaded plugins",
            extra={"plugins": list(plugins.keys())},
        )

    output_root = _ensure_output_root(Path(output_root))
    manifest_dir = _manifest_output_dir(output_root, manifest)

    results: List[Dict[str, Any]] = []

    for seed in manifest.seeds:
        res = await _run_single_seed(
            plugins=plugins,
            seed=seed,
            output_dir=manifest_dir,
            debug=debug,
        )
        results.append(res)

    # Write manifest metadata
    meta_file = manifest_dir / "manifest.json"
    with meta_file.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "manifest": asdict(manifest),
                "results": results,
                "completed_at": datetime.utcnow().isoformat(),
            },
            f,
            indent=2,
            default=str,
        )

    if debug:
        log.info(
            "Trace manifest completed",
            extra={"manifest": manifest.name, "output_dir": str(manifest_dir)},
        )

    return {
        "manifest": manifest.name,
        "output_dir": str(manifest_dir),
        "results": results,
    }


def run_multi_chain_trace_v2(
    manifest: TraceManifestV2,
    output_root: str | Path,
    debug: bool = False,
) -> Dict[str, Any]:
    """
    Synchronous wrapper for CLI/GUI.
    """
    return asyncio.run(
        run_multi_chain_trace_v2_async(
            manifest=manifest,
            output_root=output_root,
            debug=debug,
        )
    )


def _load_manifest(path: Path) -> TraceManifestV2:
    data = json.loads(path.read_text(encoding="utf-8"))
    seeds = [TraceSeed(**s) for s in data["seeds"]]
    return TraceManifestV2(
        name=data["name"],
        created_at=data.get("created_at", datetime.utcnow().isoformat()),
        seeds=seeds,
        options=data.get("options", {}),
    )


async def run_traces_v2_multi_chain_async(
    input_path: str | Path,
    output_root: str | Path,
    max_depth: int,
    max_branches: int,
    recursive: bool = True,
    debug: bool = False,
) -> None:
    """
    Batch runner: walk a directory of manifest JSON files and execute them.
    """
    input_path = Path(input_path)
    output_root = Path(output_root)

    if not input_path.exists():
        raise FileNotFoundError(f"Input path not found: {input_path}")

    manifest_files: List[Path] = []
    if input_path.is_file():
        manifest_files = [input_path]
    else:
        glob = "**/*.json" if recursive else "*.json"
        manifest_files = sorted(input_path.glob(glob))

    if debug:
        log.info(
            "Discovered manifests",
            extra={"count": len(manifest_files), "root": str(input_path)},
        )

    for mf in manifest_files:
        data = json.loads(mf.read_text(encoding="utf-8"))

        # Override depth/branches if provided
        for seed in data.get("seeds", []):
            seed.setdefault("max_depth", max_depth)
            seed.setdefault("max_branches", max_branches)

        manifest = _load_manifest(mf)
        await run_multi_chain_trace_v2_async(
            manifest=manifest,
            output_root=output_root,
            debug=debug,
        )


def run_traces_v2_multi_chain(
    input_path: str | Path,
    output_root: str | Path,
    max_depth: int,
    max_branches: int,
    recursive: bool = True,
    debug: bool = False,
) -> None:
    """
    Synchronous wrapper for batch runner.
    """
    asyncio.run(
        run_traces_v2_multi_chain_async(
            input_path=input_path,
            output_root=output_root,
            max_depth=max_depth,
            max_branches=max_branches,
            recursive=recursive,
            debug=debug,
        )
    )
