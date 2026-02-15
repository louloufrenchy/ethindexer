-- Example: adjust source table name as needed (transactions_v1)
INSERT INTO tron_transactions (txid, block_number, ts, status)
SELECT
    txid,
    block_number,
    to_timestamp(timestamp / 1000.0) AT TIME ZONE 'UTC',
    status
FROM transactions_v1
ON CONFLICT DO NOTHING;
