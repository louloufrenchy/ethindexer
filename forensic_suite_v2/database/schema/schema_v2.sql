CREATE TABLE index_checkpoint (
    id SERIAL PRIMARY KEY,
    chain TEXT NOT NULL,
    last_block BIGINT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE indexer_metrics (
    id SERIAL PRIMARY KEY,
    chain TEXT NOT NULL,
    metric_name TEXT NOT NULL,
    metric_value DOUBLE PRECISION NOT NULL,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- eth
CREATE TABLE eth_blocks (...);
CREATE TABLE eth_transactions (...);

-- btc
CREATE TABLE btc_blocks (...);
CREATE TABLE btc_transactions (...);

-- tron
CREATE TABLE tron_blocks (...);
CREATE TABLE tron_transactions (...);
