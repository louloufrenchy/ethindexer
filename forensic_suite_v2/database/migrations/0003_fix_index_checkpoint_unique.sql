-- 0003_fix_index_checkpoint_unique.sql

-- Clean duplicates if any (keep lowest id)
DELETE FROM index_checkpoint a
USING index_checkpoint b
WHERE a.chain = b.chain
  AND a.id > b.id;

-- Add the required UNIQUE constraint
ALTER TABLE index_checkpoint
    ADD CONSTRAINT index_checkpoint_chain_unique UNIQUE (chain);
