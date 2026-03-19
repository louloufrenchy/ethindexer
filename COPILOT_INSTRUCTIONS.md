# Copilot Agent Instructions for forensic_suite_v2

## Purpose
This repository contains a unified multi-chain forensic suite supporting BTC, ETH, and TRON. Copilot should assist with orchestration, indexer logic, SQL schema evolution, and multi-chain coordination.

## Key Directories
- btc_indexer/: Bitcoin indexer logic
- eth_indexer/: Ethereum indexer logic
- tron_indexer/: TRON indexer logic
- core/: shared engine, plugin loader, and abstractions
- plugins/: chain-specific plugin implementations
- dashboards/: Grafana and PowerShell dashboards
- scripts/: operational scripts
- tools/: environment loaders and validators

## Expectations
- Maintain deterministic, reproducible behavior
- Prefer modular, testable code
- Ensure chain isolation while supporting unified orchestration
- Follow pyproject.toml packaging rules
- Use chains.json as the source of truth for chain metadata
