-- ============================================================
-- TRON / ETH / BTC INDEXER DATABASE SCHEMA (VERSION 2 ONLY)
-- ============================================================
-- Target: fresh deployment, no legacy v1 tables, fully partition-ready
-- Role: assumes application connects as user "tron"
-- ============================================================

-- ============================================================
-- EXTENSIONS
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ============================================================
-- SHARED: token_registry
-- ============================================================
CREATE TABLE IF NOT EXISTS token_registry (
    contract_address TEXT PRIMARY KEY,
    symbol           TEXT,
    name             TEXT,
    decimals         INTEGER
);

GRANT INSERT, SELECT, UPDATE, DELETE ON token_registry TO tron;

-- ============================================================
-- SHARED: index_checkpoint (per-chain via id)
-- id = 1 → TRON, 2 → ETH, 3 → BTC
-- ============================================================
CREATE TABLE IF NOT EXISTS index_checkpoint (
    id         INTEGER PRIMARY KEY,
    last_block BIGINT NOT NULL
);

INSERT INTO index_checkpoint (id, last_block)
VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO index_checkpoint (id, last_block)
VALUES (2, 0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO index_checkpoint (id, last_block)
VALUES (3, 0)
ON CONFLICT (id) DO NOTHING;

GRANT INSERT, SELECT, UPDATE, DELETE ON index_checkpoint TO tron;

-- ============================================================
-- SHARED: indexer_metrics (multi-chain)
-- ============================================================
CREATE TABLE IF NOT EXISTS indexer_metrics (
    ts         TIMESTAMPTZ NOT NULL,
    chain      TEXT        NOT NULL,  -- 'tron', 'eth', 'btc'
    last_block BIGINT      NOT NULL,
    chain_head BIGINT      NOT NULL,
    lag        BIGINT      NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_indexer_metrics_chain_ts
    ON indexer_metrics(chain, ts DESC);

GRANT INSERT, SELECT, UPDATE, DELETE ON indexer_metrics TO tron;

-- ============================================================
-- TRON v2
-- ============================================================

-- TRON transactions (partitioned by timestamp)
CREATE TABLE IF NOT EXISTS tron_transactions (
    txid         TEXT        NOT NULL,
    block_number BIGINT      NOT NULL,
    ts           TIMESTAMPTZ NOT NULL,
    status       TEXT,
    PRIMARY KEY (txid, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS tron_transactions_default
    PARTITION OF tron_transactions
    DEFAULT;

-- TRC20 transfers (partitioned by timestamp)
CREATE TABLE IF NOT EXISTS trc20_transfers (
    id              BIGSERIAL,
    txid            TEXT        NOT NULL,
    log_index       INTEGER     NOT NULL,
    contract_address TEXT       NOT NULL,
    from_address    TEXT        NOT NULL,
    to_address      TEXT        NOT NULL,
    amount_raw      TEXT        NOT NULL,
    block_number    BIGINT      NOT NULL,
    ts              TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS trc20_transfers_default
    PARTITION OF trc20_transfers
    DEFAULT;

-- Address transaction index (partitioned by timestamp)
CREATE TABLE IF NOT EXISTS address_tx_index (
    id              BIGSERIAL,
    address         TEXT        NOT NULL,
    txid            TEXT        NOT NULL,
    direction       TEXT        NOT NULL, -- 'in' or 'out'
    contract_address TEXT       NOT NULL,
    amount_raw      TEXT        NOT NULL,
    block_number    BIGINT      NOT NULL,
    ts              TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS address_tx_index_default
    PARTITION OF address_tx_index
    DEFAULT;

-- TRX native transfers (non-partitioned, small volume)
CREATE TABLE IF NOT EXISTS trx_transfers (
    id           BIGSERIAL PRIMARY KEY,
    txid         TEXT    NOT NULL,
    from_address TEXT    NOT NULL,
    to_address   TEXT    NOT NULL,
    amount       BIGINT  NOT NULL,
    block_number BIGINT  NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_trx_from
    ON trx_transfers(from_address);

CREATE INDEX IF NOT EXISTS idx_trx_to
    ON trx_transfers(to_address);

CREATE INDEX IF NOT EXISTS idx_trx_block
    ON trx_transfers(block_number);

-- TRON block hashes (for reorg detection)
CREATE TABLE IF NOT EXISTS tron_block_hashes (
    block_number BIGINT PRIMARY KEY,
    block_hash   TEXT   NOT NULL
);

GRANT INSERT, SELECT, UPDATE, DELETE ON
    tron_transactions,
    tron_transactions_default,
    trc20_transfers,
    trc20_transfers_default,
    address_tx_index,
    address_tx_index_default,
    trx_transfers,
    tron_block_hashes
TO tron;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO tron;

-- ============================================================
-- ETH v2
-- ============================================================

-- ETH transactions (partitioned by timestamp)
CREATE TABLE IF NOT EXISTS eth_transactions (
    tx_hash      TEXT        NOT NULL,
    block_number BIGINT      NOT NULL,
    ts           TIMESTAMPTZ NOT NULL,
    status       TEXT,
    PRIMARY KEY (tx_hash, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS eth_transactions_default
    PARTITION OF eth_transactions
    DEFAULT;

-- ERC20 transfers (partitioned by timestamp)
CREATE TABLE IF NOT EXISTS erc20_transfers (
    id              BIGSERIAL,
    tx_hash         TEXT        NOT NULL,
    log_index       INTEGER     NOT NULL,
    contract_address TEXT       NOT NULL,
    from_address    TEXT        NOT NULL,
    to_address      TEXT        NOT NULL,
    amount_raw      TEXT        NOT NULL,
    block_number    BIGINT      NOT NULL,
    ts              TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS erc20_transfers_default
    PARTITION OF erc20_transfers
    DEFAULT;

-- ETH address index (partitioned by timestamp)
CREATE TABLE IF NOT EXISTS eth_address_index (
    id              BIGSERIAL,
    address         TEXT        NOT NULL,
    tx_hash         TEXT        NOT NULL,
    direction       TEXT        NOT NULL,
    contract_address TEXT,
    amount_raw      TEXT,
    block_number    BIGINT      NOT NULL,
    ts              TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS eth_address_index_default
    PARTITION OF eth_address_index
    DEFAULT;

GRANT INSERT, SELECT, UPDATE, DELETE ON
    eth_transactions,
    eth_transactions_default,
    erc20_transfers,
    erc20_transfers_default,
    eth_address_index,
    eth_address_index_default
TO tron;

-- ============================================================
-- BTC v2
-- ============================================================

-- BTC blocks (partitioned by timestamp)
CREATE TABLE IF NOT EXISTS btc_blocks (
    block_hash TEXT        NOT NULL,
    height     BIGINT      NOT NULL,
    ts         TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (block_hash, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS btc_blocks_default
    PARTITION OF btc_blocks
    DEFAULT;

CREATE INDEX IF NOT EXISTS idx_btc_blocks_height
    ON btc_blocks(height);

-- BTC transactions (partitioned by timestamp)
CREATE TABLE IF NOT EXISTS btc_transactions (
    txid         TEXT        NOT NULL,
    block_hash   TEXT        NOT NULL,
    block_height BIGINT      NOT NULL,
    ts           TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (txid, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS btc_transactions_default
    PARTITION OF btc_transactions
    DEFAULT;

CREATE INDEX IF NOT EXISTS idx_btc_tx_block
    ON btc_transactions(block_height);

-- BTC UTXOs (partitioned by timestamp)
CREATE TABLE IF NOT EXISTS btc_utxos (
    id          BIGSERIAL,
    txid        TEXT        NOT NULL,
    vout        INTEGER     NOT NULL,
    address     TEXT,
    amount_sats BIGINT      NOT NULL,
    spent       BOOLEAN     DEFAULT FALSE,
    spent_by_txid TEXT,
    ts          TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);

CREATE TABLE IF NOT EXISTS btc_utxos_default
    PARTITION OF btc_utxos
    DEFAULT;

CREATE INDEX IF NOT EXISTS idx_btc_utxos_address
    ON btc_utxos(address);

CREATE INDEX IF NOT EXISTS idx_btc_utxos_spent
    ON btc_utxos(spent);

GRANT INSERT, SELECT, UPDATE, DELETE ON
    btc_blocks,
    btc_blocks_default,
    btc_transactions,
    btc_transactions_default,
    btc_utxos,
    btc_utxos_default
TO tron;

GRANT USAGE, SELECT ON SEQUENCE btc_utxos_id_seq TO tron;

-- ============================================================
-- BTC PARTITION FUNCTION (used by v2 indexer)
-- ============================================================
DROP FUNCTION IF EXISTS ensure_btc_monthly_partition(text, timestamptz);

CREATE FUNCTION ensure_btc_monthly_partition(parent_table text, ts timestamptz)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    part_suffix text;
    part_name   text;
BEGIN
    -- e.g. btc_blocks_2009_01
    part_suffix := to_char(ts, 'YYYY_MM');
    part_name   := parent_table || '_' || part_suffix;

    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF %I
         FOR VALUES FROM (%L) TO (%L)',
        part_name,
        parent_table,
        date_trunc('month', ts),
        (date_trunc('month', ts) + interval '1 month')
    );
END;
$$;

GRANT EXECUTE ON FUNCTION ensure_btc_monthly_partition(text, timestamptz) TO tron;

-- ============================================================
-- OWNERSHIP (optional if created as tron; otherwise run these)
-- ============================================================
ALTER TABLE token_registry OWNER TO tron;
ALTER TABLE index_checkpoint OWNER TO tron;
ALTER TABLE indexer_metrics OWNER TO tron;

ALTER TABLE tron_transactions OWNER TO tron;
ALTER TABLE tron_transactions_default OWNER TO tron;
ALTER TABLE trc20_transfers OWNER TO tron;
ALTER TABLE trc20_transfers_default OWNER TO tron;
ALTER TABLE address_tx_index OWNER TO tron;
ALTER TABLE address_tx_index_default OWNER TO tron;
ALTER TABLE trx_transfers OWNER TO tron;
ALTER TABLE tron_block_hashes OWNER TO tron;

ALTER TABLE eth_transactions OWNER TO tron;
ALTER TABLE eth_transactions_default OWNER TO tron;
ALTER TABLE erc20_transfers OWNER TO tron;
ALTER TABLE erc20_transfers_default OWNER TO tron;
ALTER TABLE eth_address_index OWNER TO tron;
ALTER TABLE eth_address_index_default OWNER TO tron;

ALTER TABLE btc_blocks OWNER TO tron;
ALTER TABLE btc_blocks_default OWNER TO tron;
ALTER TABLE btc_transactions OWNER TO tron;
ALTER TABLE btc_transactions_default OWNER TO tron;
ALTER TABLE btc_utxos OWNER TO tron;
ALTER TABLE btc_utxos_default OWNER TO tron;

-- ============================================================
-- VIEWS FOR TRACERS + GRAFANA
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

