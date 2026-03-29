from __future__ import annotations

import asyncio
import json
from typing import Any

from fastapi import FastAPI, Query, Request, Body
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.encoders import jsonable_encoder
from datetime import date, datetime, time
from decimal import Decimal
from uuid import UUID
import base64

from forensic_suite_v2.dashboards.data import DashboardDataService
from forensic_suite_v2.dashboards.data.manager import ServiceManager
from forensic_suite_v2.tracer import TraceEngine, TraceQuery, to_cytoscape_elements


app = FastAPI(title="Forensic Cluster Dashboard")

manager = ServiceManager()
service = DashboardDataService()

try:
    app.mount(
        "/static",
        StaticFiles(directory="forensic_suite_v2/dashboards/web/static"),
        name="static",
    )
except Exception:
    pass


@app.on_event("startup")
async def startup_event():
    await service.connect()


@app.on_event("shutdown")
async def shutdown_event():
    close_method = getattr(service, "close", None)
    if callable(close_method):
        maybe_coro = close_method()
        if asyncio.iscoroutine(maybe_coro):
            await maybe_coro


# -------------------------------------------------------------------
# Shared HTML shell
# -------------------------------------------------------------------
def _page_shell(active_tab: str, title: str, body: str, extra_head: str = "") -> str:
    def tab_class(name: str) -> str:
        return "tab active" if name == active_tab else "tab"

    return f"""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>{title}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <style>
    :root {{
      --bg:#071327;
      --panel:#101d3b;
      --panel2:#0d1831;
      --text:#e8eefc;
      --muted:#a7b4d6;
      --line:#213562;
      --good:#30d158;
      --bad:#ff453a;
      --warn:#ffd60a;
      --accent:#6ea8ff;
    }}
    * {{ box-sizing:border-box; }}
    body {{
      margin:0;
      font-family:Segoe UI, Arial, sans-serif;
      background:var(--bg);
      color:var(--text);
    }}
    .wrap {{
      max-width:1480px;
      margin:0 auto;
      padding:24px;
    }}
    .tabs {{
      display:flex;
      gap:12px;
      margin-bottom:24px;
    }}
    .tab {{
      background:var(--panel);
      border:1px solid var(--line);
      color:var(--text);
      padding:10px 16px;
      border-radius:10px;
      text-decoration:none;
      font-weight:600;
    }}
    .tab.active {{
      outline:2px solid rgba(110,168,255,0.35);
    }}
    h1 {{
      margin:8px 0 20px;
      font-size:44px;
      font-weight:700;
    }}
    h2 {{
      margin:0 0 18px;
      font-size:22px;
    }}
    h3 {{
      margin:0 0 12px;
      font-size:18px;
    }}
    .panel {{
      background:var(--panel);
      border:1px solid var(--line);
      border-radius:18px;
      padding:18px;
      margin-bottom:18px;
      box-shadow:0 0 0 1px rgba(255,255,255,0.02) inset;
    }}
    .grid {{
      display:grid;
      grid-template-columns:1fr 1fr 1fr;
      gap:18px;
    }}
    .grid-2 {{
      display:grid;
      grid-template-columns:1fr 1fr;
      gap:18px;
    }}
    .metricbox {{
      background:var(--panel);
      border:1px solid var(--line);
      border-radius:18px;
      min-height:200px;
      padding:18px;
    }}
    table {{
      width:100%;
      border-collapse:collapse;
      table-layout:fixed;
    }}
    th, td {{
      padding:12px 10px;
      border-bottom:1px solid var(--line);
      text-align:left;
      font-size:14px;
      vertical-align:top;
      word-wrap:break-word;
    }}
    th {{
      color:var(--muted);
      font-weight:600;
    }}
    .pill {{
      display:inline-block;
      min-width:90px;
      text-align:center;
      padding:6px 10px;
      border-radius:999px;
      font-weight:700;
      font-size:12px;
      border:1px solid var(--line);
      background:var(--panel2);
    }}
    .running,.healthy {{ color:var(--good); }}
    .stopped,.down,.error {{ color:var(--bad); }}
    .unknown,.no_process,.stalled,.missing {{ color:var(--warn); }}
    .btn {{
      background:#14254d;
      color:var(--text);
      border:1px solid var(--line);
      border-radius:8px;
      padding:8px 12px;
      cursor:pointer;
      font-weight:700;
    }}
    .btn:hover {{ filter:brightness(1.08); }}
    .errbox {{
      background:#0b1020;
      border:1px solid var(--line);
      border-radius:12px;
      padding:14px;
      color:#ffb86b;
      font-family:Consolas, monospace;
      font-size:13px;
      white-space:pre-wrap;
      overflow:auto;
      max-height:260px;
    }}
    .small {{ color:var(--muted); font-size:13px; }}
    .mono {{
      font-family:Consolas, monospace;
      white-space:pre-wrap;
      overflow:auto;
    }}
    textarea {{
      width:100%;
      min-height:180px;
      background:#0b1020;
      color:var(--text);
      border:1px solid var(--line);
      border-radius:12px;
      padding:12px;
      font-family:Consolas, monospace;
      font-size:13px;
      resize:vertical;
    }}
    .row {{
      display:flex;
      gap:12px;
      align-items:center;
      flex-wrap:wrap;
      margin-bottom:14px;
    }}
    input, select {{
      background:#0b1020;
      color:var(--text);
      border:1px solid var(--line);
      border-radius:10px;
      padding:10px 12px;
    }}
    input[type="range"] {{
      width:220px;
      padding:0;
    }}
    .label {{
      color:var(--muted);
      font-size:13px;
      margin-bottom:6px;
    }}
    #cy {{
      width:100%;
      height:640px;
      background:#081126;
      border:1px solid var(--line);
      border-radius:12px;
    }}
    .resultbox {{
      background:#081126;
      border:1px solid var(--line);
      border-radius:12px;
      padding:12px;
      min-height:180px;
      overflow:auto;
    }}
  </style>
  {extra_head}
</head>
<body>
  <div class="wrap">
    <div class="tabs">
      <a class="{tab_class("overview")}" href="/">Overview</a>
      <a class="{tab_class("trace")}" href="/trace/ui">Trace UI</a>
      <a class="{tab_class("sql")}" href="/sql">SQL Console</a>
    </div>
    {body}
  </div>
</body>
</html>
"""


# -------------------------------------------------------------------
# Utility
# -------------------------------------------------------------------
def _status_pill_class(value: str | None) -> str:
    v = (value or "").lower()
    if v in {"running", "healthy"}:
        return v
    if v in {"stopped", "down", "error"}:
        return v
    if v in {"unknown", "no_process", "stalled", "missing"}:
        return v
    return "unknown"


# -------------------------------------------------------------------
# API - status / health / summary
# -------------------------------------------------------------------
@app.get("/api/cluster/summary")
async def api_cluster_summary():
    summary = await service.get_cluster_summary()
    return JSONResponse(
        {
            "generated_at": str(summary.generated_at),
            "snapshots": [
                {
                    "chain": s.chain,
                    "status": s.status,
                    "last_block": s.last_block,
                    "blocks_per_min": s.blocks_per_min,
                    "age_seconds": s.age_seconds,
                }
                for s in summary.snapshots
            ],
        }
    )


@app.get("/api/cluster/status")
async def api_cluster_status():
    rows = await manager.get_cluster_status()
    return JSONResponse(
        {
            "nodes": rows,
            "last_errors": manager.last_errors,
        }
    )


@app.get("/api/cluster/health")
async def api_cluster_health():
    rows = await manager.get_cluster_health_summary()
    return JSONResponse({"health": rows})


@app.post("/api/service/{chain}/{svc}/{action}")
async def api_control_service(chain: str, svc: str, action: str):
    ok = await manager.control_service(chain, svc, action)
    return JSONResponse(
        {
            "ok": ok,
            "chain": chain,
            "service": svc,
            "action": action,
            "last_error": manager.last_errors.get(manager.nodes.get(chain, {}).get("ip", ""), ""),
        }
    )


# -------------------------------------------------------------------
# API - unrestricted SQL
# -------------------------------------------------------------------
def _sql_safe(value):
    if value is None:
        return None

    if isinstance(value, (str, int, float, bool)):
        return value

    if isinstance(value, (datetime, date, time)):
        return value.isoformat()

    if isinstance(value, Decimal):
        return str(value)

    if isinstance(value, UUID):
        return str(value)

    if isinstance(value, (bytes, bytearray, memoryview)):
        return base64.b64encode(bytes(value)).decode("ascii")

    if isinstance(value, dict):
        return {str(k): _sql_safe(v) for k, v in value.items()}

    if isinstance(value, (list, tuple, set)):
        return [_sql_safe(v) for v in value]

    return str(value)

@app.post("/api/sql/query")
async def api_sql_query(payload: dict = Body(...)):
    query = (payload.get("query") or "").strip()
    if not query:
        return JSONResponse({"ok": False, "error": "Empty query"}, status_code=400)

    pool = service.pool
    if pool is None:
        return JSONResponse(
            {"ok": False, "error": "Database pool is not connected"},
            status_code=500,
        )

    lowered = query.lstrip().lower()
    fetch_mode = lowered.startswith(("select", "with", "show", "explain"))

    try:
        async with pool.acquire() as conn:
            if fetch_mode:
                rows = await conn.fetch(query)
                safe_rows = []

                for row in rows:
                    safe_rows.append(
                        {str(k): _sql_safe(v) for k, v in dict(row).items()}
                    )

                return JSONResponse(
                    {
                        "ok": True,
                        "mode": "fetch",
                        "row_count": len(safe_rows),
                        "rows": safe_rows,
                    }
                )

            status = await conn.execute(query)
            return JSONResponse(
                {
                    "ok": True,
                    "mode": "execute",
                    "status": status,
                }
            )

    except Exception as exc:
        return JSONResponse(
            {
                "ok": False,
                "error": str(exc),
            },
            status_code=500,
        )

# -------------------------------------------------------------------
# API - trace
# -------------------------------------------------------------------
@app.get("/trace/exists")
async def trace_exists(
    address: str = Query(..., min_length=1),
    chain: str | None = Query(default=None),
) -> dict:
    async with service.pool.acquire() as conn:
        base_sql = """
            SELECT chain, COUNT(*) AS row_count, MIN(ts) AS first_seen, MAX(ts) AS last_seen
            FROM v_all_flows
            WHERE lower(address) = lower($1)
        """
        args = [address]
        if chain:
            sql = base_sql + " AND chain = $2 GROUP BY chain ORDER BY chain"
            args.append(chain.lower())
        else:
            sql = base_sql + " GROUP BY chain ORDER BY chain"
        rows = await conn.fetch(sql, *args)

    exists = len(rows) > 0
    chains = [r["chain"] for r in rows]
    per_chain = {
        r["chain"]: {
            "row_count": int(r["row_count"]),
            "first_seen": r["first_seen"].isoformat() if r["first_seen"] else None,
            "last_seen": r["last_seen"].isoformat() if r["last_seen"] else None,
        }
        for r in rows
    }
    first_seen = min([r["first_seen"] for r in rows if r["first_seen"] is not None], default=None)
    last_seen = max([r["last_seen"] for r in rows if r["last_seen"] is not None], default=None)

    return {
        "address": address,
        "chain_filter": chain,
        "exists": exists,
        "chains": chains,
        "per_chain": per_chain,
        "first_seen": first_seen.isoformat() if first_seen else None,
        "last_seen": last_seen.isoformat() if last_seen else None,
    }


@app.get("/trace")
async def trace(
    address: str = Query(..., min_length=1),
    chain: str | None = Query(default=None),
    max_depth: int = Query(default=2, ge=1, le=6),
    max_nodes: int = Query(default=250, ge=10, le=5000),
    max_edges: int = Query(default=500, ge=10, le=10000),
    tx_limit_per_address: int = Query(default=150, ge=1, le=2000),
    counterpart_limit_per_tx: int = Query(default=40, ge=2, le=1000),
) -> dict:
    engine = TraceEngine(service.pool)
    result = await engine.trace(
        TraceQuery(
            address=address,
            chain=chain,
            max_depth=max_depth,
            max_nodes=max_nodes,
            max_edges=max_edges,
            tx_limit_per_address=tx_limit_per_address,
            counterpart_limit_per_tx=counterpart_limit_per_tx,
        )
    )
    return result.to_dict()


@app.get("/trace/cytoscape")
async def trace_cytoscape(
    address: str = Query(..., min_length=1),
    chain: str | None = Query(default=None),
    max_depth: int = Query(default=2, ge=1, le=6),
    max_nodes: int = Query(default=250, ge=10, le=5000),
    max_edges: int = Query(default=500, ge=10, le=10000),
    tx_limit_per_address: int = Query(default=150, ge=1, le=2000),
    counterpart_limit_per_tx: int = Query(default=40, ge=2, le=1000),
) -> dict:
    engine = TraceEngine(service.pool)
    result = await engine.trace(
        TraceQuery(
            address=address,
            chain=chain,
            max_depth=max_depth,
            max_nodes=max_nodes,
            max_edges=max_edges,
            tx_limit_per_address=tx_limit_per_address,
            counterpart_limit_per_tx=counterpart_limit_per_tx,
        )
    )
    return {
        "elements": to_cytoscape_elements(result),
        "stats": result.stats,
        "alerts": [a.to_dict() for a in result.alerts],
    }


# -------------------------------------------------------------------
# HTML - Overview
# -------------------------------------------------------------------
@app.get("/", response_class=HTMLResponse)
async def overview():
    body = """
    <h1>Distributed Cluster Orchestrator</h1>

    <div class="panel">
      <h2>Node Management (SSH)</h2>
      <table>
        <thead>
          <tr>
            <th style="width:22%">IP</th>
            <th style="width:14%">Chain</th>
            <th style="width:22%">Service</th>
            <th style="width:14%">Status</th>
            <th style="width:14%">Health</th>
            <th style="width:14%">Action</th>
          </tr>
        </thead>
        <tbody id="node-table">
          <tr><td colspan="6">Loading...</td></tr>
        </tbody>
      </table>

      <div style="margin-top:16px">
        <div class="small" style="margin-bottom:8px">Remote diagnostics:</div>
        <div id="errors" class="errbox">Loading...</div>
      </div>
    </div>

    <div class="grid">
      <div class="metricbox">
        <h2>ETH</h2>
        <div id="eth-box" class="small">Loading...</div>
      </div>
      <div class="metricbox">
        <h2>TRON</h2>
        <div id="tron-box" class="small">Loading...</div>
      </div>
      <div class="metricbox">
        <h2>BTC</h2>
        <div id="btc-box" class="small">Loading...</div>
      </div>
    </div>

<script>
async function fetchJson(url, options) {
  const res = await fetch(url, options || {});
  return await res.json();
}

function pillClass(value) {
  const v = String(value || "").toLowerCase();
  if (v === "running" || v === "healthy") return "pill " + v;
  if (v === "stopped" || v === "down" || v === "error") return "pill " + v;
  if (v === "unknown" || v === "no_process" || v === "stalled" || v === "missing") return "pill " + v;
  return "pill unknown";
}

async function loadStatus() {
  const data = await fetchJson("/api/cluster/status");
  const tbody = document.getElementById("node-table");
  const nodes = data.nodes || [];

  if (!nodes.length) {
    tbody.innerHTML = "<tr><td colspan='6'>No node data.</td></tr>";
  } else {
    tbody.innerHTML = nodes.map(n => `
      <tr>
        <td>${n.node}</td>
        <td>${n.chain}</td>
        <td>${n.service}</td>
        <td><span class="${pillClass(n.status)}">${n.status}</span></td>
        <td><span class="${pillClass(n.health)}">${n.health || "UNKNOWN"}</span></td>
        <td>
          ${n.service !== "N/A"
            ? `<button class="btn" onclick="restartSvc('${n.chain}','${n.service}')">↻</button>`
            : ""}
        </td>
      </tr>
    `).join("");
  }

  const errs = data.last_errors || {};
  const errLines = Object.keys(errs).length
    ? Object.entries(errs).map(([k,v]) => `[${k}] ${v}`).join("\\n")
    : "No remote errors.";
  document.getElementById("errors").textContent = errLines;
}

async function loadSummary() {
  const data = await fetchJson("/api/cluster/summary");
  const snaps = data.snapshots || [];
  const byChain = {};
  snaps.forEach(s => byChain[(s.chain || "").toLowerCase()] = s);

  ["eth","tron","btc"].forEach(chain => {
    const el = document.getElementById(chain + "-box");
    const s = byChain[chain];
    if (!s) {
      el.innerHTML = "No data.";
      return;
    }
    el.innerHTML = `
      <div><b>Status:</b> ${s.status}</div>
      <div><b>Last Block:</b> ${s.last_block}</div>
      <div><b>Blocks/min:</b> ${Number(s.blocks_per_min || 0).toFixed(2)}</div>
      <div><b>Age:</b> ${s.age_seconds}s</div>
      <div class="small" style="margin-top:10px">Updated: ${data.generated_at}</div>
    `;
  });
}

async function restartSvc(chain, svc) {
  await fetchJson(`/api/service/${chain}/${svc}/stop`, {method:"POST"});
  await new Promise(r => setTimeout(r, 1500));
  await fetchJson(`/api/service/${chain}/${svc}/start`, {method:"POST"});
  await loadStatus();
}

async function refreshAll() {
  try {
    await Promise.all([loadStatus(), loadSummary()]);
  } catch (e) {
    console.error(e);
  }
}

refreshAll();
setInterval(refreshAll, 15000);
</script>
    """
    return HTMLResponse(_page_shell("overview", "Forensic Cluster Dashboard", body))


# -------------------------------------------------------------------
# HTML - Trace UI
# -------------------------------------------------------------------
@app.get("/trace/ui", response_class=HTMLResponse)
async def trace_ui():
    extra_head = """
<script src="https://unpkg.com/cytoscape/dist/cytoscape.min.js"></script>
<script src="/static/cytoscape_config.js"></script>
"""
    body = """
    <h1>Trace UI</h1>

    <div class="panel">
      <h2>Trace Controls</h2>

      <div class="grid-2">
        <div>
          <div class="label">Address</div>
          <input id="trace-address" type="text" placeholder="Wallet / address">
        </div>

        <div>
          <div class="label">Chain</div>
          <select id="trace-chain">
            <option value="">(auto)</option>
            <option value="btc">btc</option>
            <option value="eth">eth</option>
            <option value="tron">tron</option>
          </select>
        </div>
      </div>

      <div class="row" style="margin-top:16px">
        <div>
          <div class="label">Depth: <span id="depth-label">2</span></div>
          <input id="trace-depth" type="range" min="1" max="6" step="1" value="2">
        </div>

        <button class="btn" onclick="checkExists()">Check Exists</button>
        <button class="btn" onclick="runTraceJson()">Run Trace JSON</button>
        <button class="btn" onclick="renderTraceGraph()">Render Graph</button>
        <button class="btn" onclick="savePng()">Save PNG</button>
      </div>

      <div class="grid-2" style="margin-top:16px">
        <div>
          <h3>Exists Result</h3>
          <div id="exists-result" class="resultbox mono">No query run yet.</div>
        </div>
        <div>
          <h3>Trace JSON</h3>
          <div id="trace-json" class="resultbox mono">No trace run yet.</div>
        </div>
      </div>
    </div>

    <div class="panel">
      <h2>Trace Graph</h2>
      <div id="trace-stats" class="small" style="margin-bottom:10px">No graph rendered yet.</div>
      <div id="cy"></div>
    </div>

<script>
let cy = null;

function currentTraceParams() {
  const address = document.getElementById("trace-address").value.trim();
  const chain = document.getElementById("trace-chain").value;
  const maxDepth = document.getElementById("trace-depth").value;

  if (!address) {
    alert("Please enter an address.");
    return null;
  }

  const params = new URLSearchParams();
  params.set("address", address);
  params.set("max_depth", maxDepth);
  if (chain) params.set("chain", chain);
  return params;
}

document.getElementById("trace-depth").addEventListener("input", function() {
  document.getElementById("depth-label").textContent = this.value;
});

async function checkExists() {
  const params = currentTraceParams();
  if (!params) return;

  const res = await fetch("/trace/exists?" + params.toString());
  const data = await res.json();
  document.getElementById("exists-result").textContent = JSON.stringify(data, null, 2);
}

async function runTraceJson() {
  const params = currentTraceParams();
  if (!params) return;

  const res = await fetch("/trace?" + params.toString());
  const data = await res.json();
  document.getElementById("trace-json").textContent = JSON.stringify(data, null, 2);
}

function defaultCyStyle() {
  return [
    {
      selector: "node",
      style: {
        "background-color": "#67b3ff",
        "label": "data(label)",
        "color": "#e8eefc",
        "font-size": "10px",
        "text-wrap": "wrap",
        "text-max-width": 120,
        "width": 24,
        "height": 24
      }
    },
    {
      selector: "edge",
      style: {
        "width": 2,
        "line-color": "#7a89b8",
        "target-arrow-color": "#7a89b8",
        "target-arrow-shape": "triangle",
        "curve-style": "bezier",
        "label": "data(label)",
        "font-size": "9px",
        "color": "#a7b4d6"
      }
    },
    {
      selector: ".root",
      style: {
        "background-color": "#ffd60a",
        "width": 32,
        "height": 32
      }
    }
  ];
}

async function renderTraceGraph() {
  const params = currentTraceParams();
  if (!params) return;

  const res = await fetch("/trace/cytoscape?" + params.toString());
  const data = await res.json();

  const style = (window.FS2_CY_STYLE && Array.isArray(window.FS2_CY_STYLE))
    ? window.FS2_CY_STYLE
    : defaultCyStyle();

  cy = cytoscape({
    container: document.getElementById("cy"),
    elements: data.elements || [],
    style: style,
    layout: {
      name: "breadthfirst",
      directed: true,
      padding: 24,
      spacingFactor: 1.25
    }
  });

  const stats = data.stats || {};
  document.getElementById("trace-stats").textContent =
    "nodes=" + (stats.node_count ?? "n/a") +
    " | edges=" + (stats.edge_count ?? "n/a") +
    " | root=" + (stats.root_address ?? "n/a");
}

function savePng() {
  if (!cy) {
    alert("Render a graph first.");
    return;
  }

  const png64 = cy.png({
    full: true,
    scale: 2,
    bg: "#071327"
  });

  const a = document.createElement("a");
  a.href = png64;
  a.download = "trace_graph.png";
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}
</script>
    """
    return HTMLResponse(_page_shell("trace", "Trace UI", body, extra_head=extra_head))


# -------------------------------------------------------------------
# HTML - SQL Console
# -------------------------------------------------------------------
@app.get("/sql", response_class=HTMLResponse)
async def sql_ui():
    body = """
    <h1>SQL Console</h1>

    <div class="panel">
      <h2>Live SQL Query Console</h2>
      <div class="small" style="margin-bottom:12px">
        Executes SQL directly against the connected forensic database.
      </div>

      <textarea id="sql-text">SELECT * FROM btc_utxos LIMIT 5;</textarea>

      <div class="row" style="margin-top:14px">
        <button class="btn" onclick="runSql()">Run SQL</button>
        <button class="btn" onclick="clearSqlResult()">Clear Result</button>
      </div>

      <div style="margin-top:16px">
        <div class="small" style="margin-bottom:8px">Result:</div>
        <div id="sql-result" class="errbox">Waiting for query...</div>
      </div>
    </div>

<script>
async function runSql() {
  const query = document.getElementById("sql-text").value;
  const res = await fetch("/api/sql/query", {
    method: "POST",
    headers: {"Content-Type":"application/json"},
    body: JSON.stringify({query})
  });

  const data = await res.json();
  document.getElementById("sql-result").textContent = JSON.stringify(data, null, 2);
}

function clearSqlResult() {
  document.getElementById("sql-result").textContent = "Waiting for query...";
}
</script>
    """
    return HTMLResponse(_page_shell("sql", "SQL Console", body))
