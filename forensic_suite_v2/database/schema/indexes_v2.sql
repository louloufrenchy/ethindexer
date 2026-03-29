CREATE INDEX idx_eth_blocks_number ON eth_blocks (number);
CREATE INDEX idx_eth_transactions_block ON eth_transactions (block_number);

CREATE INDEX idx_btc_blocks_height ON btc_blocks (height);
CREATE INDEX idx_btc_transactions_block ON btc_transactions (height);

CREATE INDEX idx_tron_blocks_number ON tron_blocks (number);
CREATE INDEX idx_tron_transactions_block ON tron_transactions (block_number);

CREATE INDEX idx_index_checkpoint_chain ON index_checkpoint (chain);
