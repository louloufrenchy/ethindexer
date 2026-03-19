# Path to psql.exe — adjust if your version differs
$psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

# Database connection info
$db = "tron_index"
$user = "postgres"

# SQL to apply all grants for TRON + ETH + BTC
$sql = @"
-- TRON tables
GRANT INSERT, SELECT, UPDATE, DELETE ON transactions TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON trc20_transfers TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON address_tx_index TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON trx_transfers TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON token_registry TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON block_hashes TO tron;

-- ETH tables
GRANT INSERT, SELECT, UPDATE, DELETE ON eth_transactions TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON erc20_transfers TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON eth_address_index TO tron;

-- BTC tables
GRANT INSERT, SELECT, UPDATE, DELETE ON btc_transactions TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON btc_address_index TO tron;

-- Shared tables
GRANT INSERT, SELECT, UPDATE, DELETE ON indexer_metrics TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON index_checkpoint TO tron;

-- Sequences (TRON)
GRANT USAGE, SELECT ON SEQUENCE trc20_transfers_id_seq TO tron;
GRANT USAGE, SELECT ON SEQUENCE address_tx_index_id_seq TO tron;

-- Sequences (ETH)
GRANT USAGE, SELECT ON SEQUENCE erc20_transfers_id_seq TO tron;
GRANT USAGE, SELECT ON SEQUENCE eth_address_index_id_seq TO tron;

-- Sequences (BTC)
GRANT INSERT, SELECT, UPDATE, DELETE ON btc_blocks TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON btc_transactions TO tron;
GRANT INSERT, SELECT, UPDATE, DELETE ON btc_utxos TO tron;

-- BTC sequences
GRANT USAGE, SELECT ON SEQUENCE btc_utxos_id_seq TO tron;
"@

# Execute the SQL
& $psql -U $user -d $db -c "$sql"
