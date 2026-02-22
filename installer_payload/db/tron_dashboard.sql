\pset pager off

-- Colors
\set COLOR_RESET  E'\033[0m'
\set COLOR_TRON   E'\033[32m'
\set COLOR_BTC    E'\033[33m'
\set COLOR_ETH    E'\033[36m'
\set COLOR_TITLE  E'\033[35m'

\echo :COLOR_TITLE '=== 1) Latest TRON blocks (transactions) ===' :COLOR_RESET
SELECT
    block_number,
    COUNT(*) AS tx_count,
    MIN(ts) AS first_ts,
    MAX(ts) AS last_ts
FROM transactions
GROUP BY block_number
ORDER BY block_number DESC
LIMIT 10;

\echo
\echo :COLOR_BTC '=== 1b) Latest BTC blocks ===' :COLOR_RESET
SELECT
    height AS block_height,
    COUNT(t.txid) AS tx_count,
    MIN(t.ts) AS first_ts,
    MAX(t.ts) AS last_ts
FROM btc_blocks b
LEFT JOIN btc_transactions t
  ON t.block_height = b.height
GROUP BY b.height
ORDER BY b.height DESC
LIMIT 10;

\echo
\echo :COLOR_ETH '=== 1c) Latest ETH blocks ===' :COLOR_RESET
SELECT
    block_number,
    COUNT(*) AS tx_count,
    MIN(ts) AS first_ts,
    MAX(ts) AS last_ts
FROM eth_transactions
GROUP BY block_number
ORDER BY block_number DESC
LIMIT 10;

\echo
\echo :COLOR_TRON '=== 2) Latest TRC20 transfers (TRON) ===' :COLOR_RESET
SELECT
    ts,
    txid,
    contract_address,
    from_address,
    to_address,
    amount_raw,
    block_number
FROM trc20_transfers
ORDER BY ts DESC
LIMIT 10;

\echo
\echo :COLOR_ETH '=== 2b) Latest ERC20 transfers (ETH) ===' :COLOR_RESET
SELECT
    ts,
    tx_hash,
    contract_address,
    from_address,
    to_address,
    amount_raw,
    block_number
FROM erc20_transfers
ORDER BY ts DESC
LIMIT 10;

\echo
\echo :COLOR_BTC '=== 2c) BTC UTXO growth (recent) ===' :COLOR_RESET
SELECT
    date_trunc('hour', ts) AS hour,
    COUNT(*) AS utxo_created
FROM btc_utxos
GROUP BY date_trunc('hour', ts)
ORDER BY hour DESC
LIMIT 24;

\echo
\echo :COLOR_TITLE '=== 3) Ingestion lag (indexer_metrics) ===' :COLOR_RESET
SELECT
    ts,
    chain,
    last_block,
    chain_head,
    lag,
    lag AS computed_lag
FROM indexer_metrics
WHERE chain IN ('tron', 'btc', 'eth')
ORDER BY ts DESC
LIMIT 10;

\echo
\echo :COLOR_TITLE '=== 4) Partition usage (row counts per partition) ===' :COLOR_RESET
WITH parts AS (
    SELECT
        c.relname AS partition,
        p.relname AS parent,
        n.nspname AS schema_name
    FROM pg_inherits
    JOIN pg_class c ON c.oid = inhrelid
    JOIN pg_class p ON p.oid = inhparent
    JOIN pg_namespace n ON n.oid = c.relnamespace
),
counts AS (
    SELECT
        parent AS table_name,
        partition,
        (SELECT COUNT(*) FROM pg_catalog.pg_class pc
         JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
         WHERE pc.relname = partition
           AND pn.nspname = 'public') AS dummy -- placeholder
)
SELECT
    p.parent AS table_name,
    p.partition,
    (SELECT COUNT(*) FROM public."%I") AS row_count
FROM parts p
JOIN LATERAL (
    SELECT format('%I', p.partition) AS part_name
) f ON TRUE
WHERE p.parent IN (
    'transactions',
    'trc20_transfers',
    'contract_log_density',
    'address_tx_index',
    'btc_blocks',
    'btc_transactions',
    'btc_utxos',
    'eth_blocks',
    'eth_transactions',
    'eth_logs',
    'erc20_transfers',
    'eth_address_index'
)
ORDER BY table_name, partition;

\echo
\echo :COLOR_TRON '=== 5) TRON contract log density (recent) ===' :COLOR_RESET
SELECT
    contract_address,
    COUNT(*) AS total_logs,
    MIN(ts) AS first_ts,
    MAX(ts) AS last_ts
FROM contract_log_density
GROUP BY contract_address
ORDER BY total_logs DESC
LIMIT 10;

\echo
\echo :COLOR_ETH '=== 5b) ETH contract log density (recent) ===' :COLOR_RESET
SELECT
    contract_address,
    COUNT(*) AS total_logs,
    MIN(ts) AS first_ts,
    MAX(ts) AS last_ts
FROM eth_logs
GROUP BY contract_address
ORDER BY total_logs DESC
LIMIT 10;

\echo
\echo :COLOR_TITLE '=== END DASHBOARD REFRESH ===' :COLOR_RESET
