-- wrapper to include views
\i views_v2.sql
-- ============================================================
-- FORENSIC SUITE v2 – VIEWS
-- ============================================================

CREATE OR REPLACE VIEW v_tron_flows AS
SELECT
    address,
    txid,
    direction,
    contract_address,
    amount_raw,
    block_number,
    ts
FROM address_tx_index;

CREATE OR REPLACE VIEW v_eth_flows AS
SELECT
    address,
    tx_hash AS txid,
    direction,
    contract_address,
    amount_raw,
    block_number,
    ts
FROM eth_address_index;

CREATE OR REPLACE VIEW v_btc_utxo_flows AS
SELECT
    txid,
    vout,
    address,
    amount_sats,
    spent,
    spent_by_txid,
    ts
FROM btc_utxos;

CREATE OR REPLACE VIEW v_btc_tx AS
SELECT
    txid,
    block_hash,
    block_height,
    ts
FROM btc_transactions;

CREATE OR REPLACE VIEW v_all_flows AS
SELECT
    'tron' AS chain,
    address,
    txid,
    direction,
    contract_address,
    amount_raw,
    block_number,
    ts
FROM v_tron_flows

UNION ALL

SELECT
    'eth' AS chain,
    address,
    txid,
    direction,
    contract_address,
    amount_raw,
    block_number,
    ts
FROM v_eth_flows;

CREATE OR REPLACE VIEW v_forensic_cockpit AS
SELECT
    'tron' AS chain,
    address,
    txid,
    direction,
    contract_address,
    amount_raw,
    block_number,
    ts
FROM v_tron_flows

UNION ALL

SELECT
    'eth' AS chain,
    address,
    txid,
    direction,
    contract_address,
    amount_raw,
    block_number,
    ts
FROM v_eth_flows

UNION ALL

SELECT
    'btc' AS chain,
    u.address,
    u.txid,
    CASE WHEN u.spent THEN 'out' ELSE 'in' END AS direction,
    NULL AS contract_address,
    u.amount_sats::text AS amount_raw,
    t.block_height AS block_number,
    u.ts
FROM v_btc_utxo_flows u
LEFT JOIN v_btc_tx t ON t.txid = u.txid;
