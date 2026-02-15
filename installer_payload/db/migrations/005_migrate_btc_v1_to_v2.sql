INSERT INTO btc_blocks (block_hash, height, ts)
SELECT
    block_hash,
    height,
    to_timestamp(timestamp) AT TIME ZONE 'UTC'
FROM btc_blocks_v1
ON CONFLICT DO NOTHING;
