import requests

def tron_trigger_smart_contract(rpc_url, contract_hex, function_sig):
    # function_sig like "symbol()", "name()", "decimals()"
    # You’d encode this via ABI; here we assume pre-encoded data for brevity.
    payload = {
        "contract_address": contract_hex,
        "function_selector": function_sig,
        "owner_address": "",  # can be empty for view calls
        "parameter": "",
    }
    resp = requests.post(f"{rpc_url}/wallet/triggersmartcontract", json=payload, timeout=10)
    resp.raise_for_status()
    return resp.json()

def discover_token_metadata(conn, rpc_url, contract_hex):
    cur = conn.execute(
        "SELECT symbol, name, decimals FROM token_registry WHERE contract_address = ?",
        (contract_hex.lower(),),
    )
    row = cur.fetchone()
    if row:
        return row

    # Fetch symbol
    sym_resp = tron_trigger_smart_contract(rpc_url, contract_hex, "symbol()")
    name_resp = tron_trigger_smart_contract(rpc_url, contract_hex, "name()")
    dec_resp = tron_trigger_smart_contract(rpc_url, contract_hex, "decimals()")

    symbol = decode_string_from_result(sym_resp)
    name = decode_string_from_result(name_resp)
    decimals = decode_uint_from_result(dec_resp)

    conn.execute(
        "INSERT INTO token_registry (contract_address, symbol, name, decimals) VALUES (?, ?, ?, ?)",
        (contract_hex.lower(), symbol, name, decimals),
    )
    conn.commit()

    return symbol, name, decimals
