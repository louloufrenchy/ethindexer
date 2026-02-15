# Forensic Suite v2 – Grafana Cockpit

This dashboard visualises:

- Ingestion health per chain (`indexer_metrics`)
- TRON / ETH flow activity (`v_tron_flows`, `v_eth_flows`, `v_all_flows`)
- BTC UTXO dynamics (`v_btc_utxo_flows`)
- Address-focused multi-chain activity

## 1. Prerequisites

- Postgres running with the v2 schema:
  - `indexer_metrics`
  - `v_tron_flows`
  - `v_eth_flows`
  - `v_all_flows`
  - `v_btc_utxo_flows`
- Grafana installed and reachable (e.g. http://localhost:3000)
- The indexers running and writing into `tron_index` database

## 2. Configure the Postgres datasource

You can either:

1. Use the Grafana UI:
   - Settings → Data sources → Add data source → PostgreSQL
   - Name: `PG_TRON_INDEX`
   - Host: `localhost:5432`
   - Database: `tron_index`
   - User: `tron`
   - Password: your DB password
   - TLS: as appropriate for your environment
   - Save & Test

2. Or run the PowerShell script `configure_grafana_pg.ps1` (see below).

The datasource UID must match the JSON: `PG_TRON_INDEX`.

## 3. Import the dashboard JSON

1. Open Grafana
2. Left menu → Dashboards → Import
3. Upload `grafana_forensic_cockpit_v2.json`
4. Select the `PG_TRON_INDEX` datasource when prompted
5. Click "Import"

You should now see:

- Indexer lag per chain
- Last indexed block vs chain head
- TRON / ETH flows per minute
- BTC UTXO created vs spent
- Address activity across chains (enter an address in the `address` textbox)

## 4. Address filter

The dashboard defines a textbox variable `address`.

- Enter a TRON or ETH address
- Panels that use `v_all_flows` will filter on that address

## 5. Alignment with forensic_suite_v2

- The indexers populate the DB
- The views (`v_tron_flows`, `v_eth_flows`, `v_all_flows`, `v_btc_utxo_flows`) expose unified flows
- Grafana reads directly from Postgres
- forensic_suite_v2 tracers also read from the same DB, so the cockpit reflects exactly what the tracers see
