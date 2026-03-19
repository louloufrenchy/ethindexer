import sqlite3

class TronIndexerAdapter:
    def __init__(self, db_path):
        self.conn = sqlite3.connect(db_path)

    def outgoing_txids(self, address_hex, contract_hex):
        cursor = self.conn.execute(
            """
            SELECT txid
            FROM address_tx_index
            WHERE address = ?
              AND direction = 'out'
              AND contract_address = ?
            ORDER BY block_number ASC
            """,
            (address_hex.lower(), contract_hex.lower())
        )
        return [row[0] for row in cursor.fetchall()]
