-- wrapper to include core schema
\i schema_v2.sql
-- ============================================================
-- FORENSIC SUITE v2 – MASTER SCHEMA
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ============================================================
-- SHARED TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS token_registry (
    contract_address TEXT PRIMARY KEY,
    symbol TEXT,
    name TEXT,
    decimals INTEGER
);

CREATE TABLE IF NOT EXISTS index_checkpoint (
    id INTEGER PRIMARY KEY,
    last_block BIGINT NOT NULL
);

INSERT INTO index_checkpoint (id, last_block)
VALUES (1,0),(2,0),(3,0)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS indexer_metrics (
    ts TIMESTAMPTZ NOT NULL,
    chain TEXT NOT NULL,
    last_block BIGINT NOT NULL,
    chain_head BIGINT NOT NULL,
    lag BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_indexer_metrics_chain_ts
    ON indexer_metrics(chain, ts DESC);

-- ============================================================
-- TRON v2
-- ============================================================

CREATE TABLE IF NOT EXISTS tron_transactions (
    txid TEXT NOT NULL,
    block_number BIGINT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    status TEXT,
    PRIMARY KEY (txid, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS tron_transactions_default
    PARTITION OF tron_transactions DEFAULT;

CREATE TABLE IF NOT EXISTS trc20_transfers (
    id BIGSERIAL,
    txid TEXT NOT NULL,
    log_index INTEGER NOT NULL,
    contract_address TEXT NOT NULL,
    from_address TEXT NOT NULL,
    to_address TEXT NOT NULL,
    amount_raw TEXT NOT NULL,
    block_number BIGINT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS trc20_transfers_default
    PARTITION OF trc20_transfers DEFAULT;

CREATE TABLE IF NOT EXISTS address_tx_index (
    id BIGSERIAL,
    address TEXT NOT NULL,
    txid TEXT NOT NULL,
    direction TEXT NOT NULL,
    contract_address TEXT NOT NULL,
    amount_raw TEXT NOT NULL,
    block_number BIGINT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS address_tx_index_default
    PARTITION OF address_tx_index DEFAULT;

CREATE TABLE IF NOT EXISTS trx_transfers (
    id BIGSERIAL PRIMARY KEY,
    txid TEXT NOT NULL,
    from_address TEXT NOT NULL,
    to_address TEXT NOT NULL,
    amount BIGINT NOT NULL,
    block_number BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS tron_block_hashes (
    block_number BIGINT PRIMARY KEY,
    block_hash TEXT NOT NULL
);

-- ============================================================
-- ETH v2
-- ============================================================

CREATE TABLE IF NOT EXISTS eth_transactions (
    tx_hash TEXT NOT NULL,
    block_number BIGINT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    status TEXT,
    PRIMARY KEY (tx_hash, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS eth_transactions_default
    PARTITION OF eth_transactions DEFAULT;

CREATE TABLE IF NOT EXISTS erc20_transfers (
    id BIGSERIAL,
    tx_hash TEXT NOT NULL,
    log_index INTEGER NOT NULL,
    contract_address TEXT NOT NULL,
    from_address TEXT NOT NULL,
    to_address TEXT NOT NULL,
    amount_raw TEXT NOT NULL,
    block_number BIGINT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS erc20_transfers_default
    PARTITION OF erc20_transfers DEFAULT;

CREATE TABLE IF NOT EXISTS eth_address_index (
    id BIGSERIAL,
    address TEXT NOT NULL,
    tx_hash TEXT NOT NULL,
    direction TEXT NOT NULL,
    contract_address TEXT,
    amount_raw TEXT,
    block_number BIGINT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS eth_address_index_default
    PARTITION OF eth_address_index DEFAULT;

-- ============================================================
-- BTC v2
-- ============================================================

CREATE TABLE IF NOT EXISTS btc_blocks (
    block_hash TEXT NOT NULL,
    height BIGINT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (block_hash, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS btc_blocks_default
    PARTITION OF btc_blocks DEFAULT;

CREATE TABLE IF NOT EXISTS btc_transactions (
    txid TEXT NOT NULL,
    block_hash TEXT NOT NULL,
    block_height BIGINT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (txid, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS btc_transactions_default
    PARTITION OF btc_transactions DEFAULT;

CREATE TABLE IF NOT EXISTS btc_utxos (
    id BIGSERIAL,
    txid TEXT NOT NULL,
    vout INTEGER NOT NULL,
    address TEXT,
    amount_sats BIGINT NOT NULL,
    spent BOOLEAN DEFAULT FALSE,
    spent_by_txid TEXT,
    ts TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS btc_utxos_default
    PARTITION OF btc_utxos DEFAULT;

-- ============================================================
-- BTC PARTITION FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION ensure_btc_monthly_partition(parent_table text, ts timestamptz)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    part_suffix text;
    part_name   text;
BEGIN
    part_suffix := to_char(ts, 'YYYY_MM');
    part_name   := parent_table || '_' || part_suffix;

    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF %I
         FOR VALUES FROM (%L) TO (%L)',
        part_name,
        parent_table,
        date_trunc('month', ts),
        date_trunc('month', ts) + interval '1 month'
    );
END;
$$;
