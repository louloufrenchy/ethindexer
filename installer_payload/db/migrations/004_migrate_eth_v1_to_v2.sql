INSERT INTO eth_transactions (tx_hash, block_number, ts, status)
SELECT
    tx_hash,
    block_number,
    to_timestamp(timestamp / 1000.0) AT TIME ZONE 'UTC',
    status
FROM eth_transactions_v1
ON CONFLICT DO NOTHING;
