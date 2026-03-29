-- ============================================================
-- V2 Canonical Checkpoint Table (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS index_checkpoint (
    chain       TEXT PRIMARY KEY,
    last_block  BIGINT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure allowed chain constraint exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'index_checkpoint_chain_chk'
    ) THEN
        ALTER TABLE index_checkpoint
        ADD CONSTRAINT index_checkpoint_chain_chk
        CHECK (chain IN ('eth','btc','tron'));
    END IF;
END $$;
