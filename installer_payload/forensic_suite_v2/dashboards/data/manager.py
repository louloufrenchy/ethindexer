from __future__ import annotations

import asyncio
import json
from typing import Any

from forensic_suite_v2.dashboards.data.remote_exec import run_ssh


class ServiceManager:
    def __init__(self):
        self.nodes = {
            "eth": {
                "ip": "192.168.0.165",
                "services": ["eth_indexer", "forensic_orchestrator"],
            },
            "tron": {
                "ip": "192.168.0.172",
                "services": ["tron_indexer", "forensic_orchestrator"],
            },
            "btc": {
                "ip": "192.168.0.199",
                "services": ["btc_indexer", "forensic_orchestrator"],
            },
        }
        self.last_errors: dict[str, str] = {}

    async def get_cluster_status(self) -> list[dict[str, Any]]:
        """
        Poll all configured nodes in parallel and return flattened service rows.

        Output rows:
        {
            "node": "192.168.0.165",
            "chain": "eth",
            "service": "eth_indexer",
            "status": "RUNNING" | "STOPPED" | "MISSING" | "ERROR" | "UNKNOWN",
            "health": "HEALTHY" | "NO_PROCESS" | "DOWN" | "UNKNOWN"
        }
        """
        tasks = []
        node_meta: list[tuple[str, str, list[str]]] = []

        for chain, meta in self.nodes.items():
            ip = meta["ip"]
            services = meta["services"]

            tasks.append(run_ssh(ip, self._build_service_command(services)))
            tasks.append(run_ssh(ip, self._build_health_command()))

            node_meta.append((chain, ip, services))

        raw_results = await asyncio.gather(*tasks, return_exceptions=True)

        results: list[dict[str, Any]] = []

        for idx, (chain, ip, expected_services) in enumerate(node_meta):
            svc_result = raw_results[idx * 2]
            health_result = raw_results[idx * 2 + 1]

            health_status = self._parse_health_result(ip, health_result)

            if isinstance(svc_result, Exception):
                self.last_errors[ip] = repr(svc_result)
                results.append(
                    {
                        "node": ip,
                        "chain": chain,
                        "service": "N/A",
                        "status": "ERROR",
                        "health": health_status,
                    }
                )
                continue

            code, out, err = svc_result
            stdout = (out or "").strip()
            stderr = (err or "").strip()

            if code != 0:
                self.last_errors[ip] = stderr or stdout or f"Remote command failed with exit code {code}"
                results.append(
                    {
                        "node": ip,
                        "chain": chain,
                        "service": "N/A",
                        "status": "ERROR",
                        "health": health_status,
                    }
                )
                continue

            if not stdout:
                self.last_errors[ip] = stderr or "Empty service response"
                results.append(
                    {
                        "node": ip,
                        "chain": chain,
                        "service": "N/A",
                        "status": "ERROR",
                        "health": health_status,
                    }
                )
                continue

            try:
                services = self._parse_service_json(stdout)

                seen = set()
                for svc in services:
                    name = str(svc.get("Name", "") or "").strip()
                    status_raw = str(svc.get("Status", "") or "").strip().lower()

                    if not name:
                        continue

                    seen.add(name.lower())

                    if status_raw == "running":
                        normalized = "RUNNING"
                    elif status_raw in {"stopped", "stop pending", "start pending", "paused"}:
                        normalized = "STOPPED"
                    elif status_raw == "missing":
                        normalized = "MISSING"
                    else:
                        normalized = "UNKNOWN"

                    results.append(
                        {
                            "node": ip,
                            "chain": chain,
                            "service": name,
                            "status": normalized,
                            "health": health_status,
                        }
                    )

                # Ensure every expected service appears even if remote JSON omitted it.
                for expected in expected_services:
                    if expected.lower() not in seen:
                        results.append(
                            {
                                "node": ip,
                                "chain": chain,
                                "service": expected,
                                "status": "MISSING",
                                "health": health_status,
                            }
                        )

                if not any(r["node"] == ip for r in results):
                    # Extremely defensive fallback
                    results.append(
                        {
                            "node": ip,
                            "chain": chain,
                            "service": "N/A",
                            "status": "UNKNOWN",
                            "health": health_status,
                        }
                    )

            except Exception as exc:  # noqa: BLE001
                self.last_errors[ip] = f"JSON parse failure: {exc}; raw={stdout[:1200]}"
                results.append(
                    {
                        "node": ip,
                        "chain": chain,
                        "service": "N/A",
                        "status": "ERROR",
                        "health": health_status,
                    }
                )

        return results

    async def get_node_health(self, chain: str) -> dict[str, Any]:
        meta = self.nodes.get(chain)
        if not meta:
            return {
                "node": None,
                "chain": chain,
                "health": "UNKNOWN",
                "details": "Unknown chain",
            }

        ip = meta["ip"]

        code, out, err = await run_ssh(ip, self._build_health_command())
        stdout = (out or "").strip()
        stderr = (err or "").strip()

        if code != 0:
            self.last_errors[ip] = stderr or stdout or "Health check failed"
            return {
                "node": ip,
                "chain": chain,
                "health": "DOWN",
                "details": stderr or stdout or "Health check failed",
            }

        try:
            count = int(stdout)
            if count > 0:
                return {
                    "node": ip,
                    "chain": chain,
                    "health": "HEALTHY",
                    "details": f"python process count={count}",
                }
            return {
                "node": ip,
                "chain": chain,
                "health": "NO_PROCESS",
                "details": "No python process found",
            }
        except Exception as exc:  # noqa: BLE001
            self.last_errors[ip] = f"Health parse error: {exc}; raw={stdout[:500]}"
            return {
                "node": ip,
                "chain": chain,
                "health": "UNKNOWN",
                "details": f"Could not parse health output: {stdout[:200]}",
            }

    async def get_cluster_health_summary(self) -> list[dict[str, Any]]:
        tasks = [self.get_node_health(chain) for chain in self.nodes.keys()]
        return await asyncio.gather(*tasks)

    async def control_service(self, chain: str, svc: str, action: str) -> bool:
        meta = self.nodes.get(chain)
        if not meta:
            return False

        ip = meta["ip"]
        action = action.strip().lower()

        if action not in {"start", "stop", "query"}:
            self.last_errors[ip] = f"Unsupported service action: {action}"
            return False

        cmd = f"sc.exe {action} {svc}"
        code, out, err = await run_ssh(ip, cmd, timeout=20)

        if code != 0:
            self.last_errors[ip] = (err or "").strip() or (out or "").strip() or f"Service action failed: {action} {svc}"
            return False

        return True

    async def restart_service(self, chain: str, svc: str, delay_seconds: float = 2.0) -> bool:
        stopped = await self.control_service(chain, svc, "stop")
        await asyncio.sleep(delay_seconds)
        started = await self.control_service(chain, svc, "start")
        return stopped and started

    def _parse_health_result(self, ip: str, result: Any) -> str:
        if isinstance(result, Exception):
            self.last_errors[ip] = repr(result)
            return "DOWN"

        code, out, err = result
        stdout = (out or "").strip()
        stderr = (err or "").strip()

        if code != 0:
            self.last_errors[ip] = stderr or stdout or "Health command failed"
            return "DOWN"

        try:
            count = int(stdout)
            if count > 0:
                return "HEALTHY"
            return "NO_PROCESS"
        except Exception:
            self.last_errors[ip] = f"Health parse error: {stdout[:500]}"
            return "UNKNOWN"

    def _build_health_command(self) -> str:
        return (
            "$ErrorActionPreference='Stop'; "
            "(Get-Process python -ErrorAction SilentlyContinue | Measure-Object).Count"
        )

    def _build_service_command(self, services: list[str]) -> str:
        """
        Build a PowerShell script that returns strict JSON like:
        [
          {"Name":"eth_indexer","Status":"Running"},
          {"Name":"forensic_orchestrator","Status":"Stopped"}
        ]

        Missing services are returned as:
          {"Name":"service_name","Status":"Missing"}

        This is designed for remote_exec.run_ssh using PowerShell -EncodedCommand.
        """
        names_literal = ",".join(f"'{svc}'" for svc in services)

        return (
            "$ErrorActionPreference='Stop'; "
            f"$names=@({names_literal}); "
            "$rows=@(); "
            "foreach($n in $names){ "
            "  $svc = Get-Service -Name $n -ErrorAction SilentlyContinue; "
            "  if($null -eq $svc){ "
            "    $rows += [pscustomobject]@{ Name=$n; Status='Missing' }; "
            "  } else { "
            "    $rows += [pscustomobject]@{ Name=$svc.Name; Status=$svc.Status.ToString() }; "
            "  } "
            "}; "
            "$rows | ConvertTo-Json -Compress"
        )

    def _parse_service_json(self, stdout: str) -> list[dict[str, Any]]:
        """
        Parse stdout from the remote PowerShell service command.
        Handles:
        - normal JSON array
        - a single JSON object
        - BOM-prefixed output
        """
        cleaned = stdout.lstrip("\ufeff").strip()

        parsed = json.loads(cleaned)

        if isinstance(parsed, dict):
            parsed = [parsed]

        if not isinstance(parsed, list):
            raise ValueError(f"Unexpected parsed type: {type(parsed).__name__}")

        normalized: list[dict[str, Any]] = []
        for item in parsed:
            if not isinstance(item, dict):
                continue

            name = item.get("Name")
            status = item.get("Status")

            if name is None and status is None:
                continue

            normalized.append(
                {
                    "Name": name,
                    "Status": status,
                }
            )

        return normalized
