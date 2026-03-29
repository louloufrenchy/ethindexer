-- Ensure one row per chain in index_checkpoint
ALTER TABLE index_checkpoint
    ADD CONSTRAINT index_checkpoint_chain_unique UNIQUE (chain);

-- Example: metrics uniqueness (optional)
ALTER TABLE indexer_metrics
    ADD CONSTRAINT indexer_metrics_chain_name_time UNIQUE (chain, metric_name, recorded_at);
