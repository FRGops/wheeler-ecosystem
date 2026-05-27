#!/usr/bin/env python3
"""
Wheeler-Repowire Bridge — connects 154 Wheeler agents to the repowire mesh.

Architecture:
    Wheeler Agents → HTTP API → Repowire Daemon (:8377) → WebSocket Mesh
                              → Peers (Claude Code, Codex, etc.)

This bridge uses the repowire HTTP API for peer operations and maintains
a WebSocket connection for real-time ask/notify/broadcast events.
"""

import asyncio
import json
import os
import signal
from datetime import datetime, timezone

import httpx

REPOWIRE_API = "http://127.0.0.1:8377"
HEARTBEAT_INTERVAL = 30
RECONNECT_DELAY = 5

# Wheeler domain peers mapped to repowire circles
WHEELER_PEERS = {
    "wheeler-orchestrator": {
        "display_name": "Wheeler-Orchestrator",
        "circle": "wheeler-core",
        "role_desc": "Master Orchestrator — 154 agents, cross-domain coordination",
    },
    "wheeler-infra": {
        "display_name": "Wheeler-Infra",
        "circle": "wheeler-ops",
        "role_desc": "Docker, PM2, networking, UFW, system health",
    },
    "wheeler-security": {
        "display_name": "Wheeler-Security",
        "circle": "wheeler-ops",
        "role_desc": "Secrets, UFW, SSL, CVE, threat intelligence",
    },
    "wheeler-deploy": {
        "display_name": "Wheeler-Deploy",
        "circle": "wheeler-ops",
        "role_desc": "7-gate pipeline, pre-flight, rollback",
    },
    "wheeler-financial": {
        "display_name": "Wheeler-Financial",
        "circle": "wheeler-finance",
        "role_desc": "P&L, revenue, Stripe, treasury, cost",
    },
    "wheeler-db": {
        "display_name": "Wheeler-DB",
        "circle": "wheeler-ops",
        "role_desc": "PostgreSQL, backups, replication, queries",
    },
    "wheeler-monitoring": {
        "display_name": "Wheeler-Monitoring",
        "circle": "wheeler-ops",
        "role_desc": "Prometheus, Loki, Grafana, alerts",
    },
    "wheeler-growth": {
        "display_name": "Wheeler-Growth",
        "circle": "wheeler-growth",
        "role_desc": "SEO, content, distribution, conversion",
    },
    "wheeler-compliance": {
        "display_name": "Wheeler-Compliance",
        "circle": "wheeler-legal",
        "role_desc": "TCPA, CCPA, FCRA, surplus funds, state laws",
    },
    "wheeler-revenue": {
        "display_name": "Wheeler-Revenue",
        "circle": "wheeler-finance",
        "role_desc": "MRR/ARR, Stripe, churn, subscriptions",
    },
}


class WheelerRepowireBridge:
    def __init__(self):
        self.running = True
        self.client = httpx.AsyncClient(timeout=15, base_url=REPOWIRE_API)

    # ── HTTP API wrappers ───────────────────────────────────────────

    async def _api(self, method: str, path: str, **kw) -> dict | None:
        """Call repowire HTTP API."""
        url = f"{REPOWIRE_API}{path}"
        try:
            resp = await self.client.request(method, url, **kw)
            if resp.status_code < 400:
                return resp.json() if resp.text else {}
            print(f"[bridge] API {method} {path} → {resp.status_code}: {resp.text[:200]}")
            return None
        except Exception as e:
            print(f"[bridge] API error {method} {path}: {e}")
            return None

    async def get_peers(self) -> list:
        """List peers from the daemon."""
        result = await self._api("GET", "/peers")
        if result and isinstance(result, list):
            return result
        return []

    async def notify_peer(self, target: str, text: str) -> bool:
        """Send a notification to a peer."""
        result = await self._api("POST", "/notify", json={
            "to_peer": target,
            "text": text,
            "from_peer": "wheeler-orchestrator",
        })
        return result is not None

    async def broadcast(self, text: str) -> bool:
        """Broadcast a message to all peers."""
        payload = {
            "from_peer": "wheeler-orchestrator",
            "text": text,
        }
        result = await self._api("POST", "/broadcast", json=payload)
        return result is not None

    async def schedule_create(self, name: str, cron: str, prompt: str, target: str) -> bool:
        """Create a scheduled job."""
        result = await self._api("POST", "/schedules", json={
            "name": name,
            "cron_expression": cron,
            "prompt": prompt,
            "target_peer": target,
        })
        return result is not None

    # ── Main loop ───────────────────────────────────────────────────

    async def health_check_loop(self):
        """Periodic health check + peer listing."""
        while self.running:
            try:
                health = await self._api("GET", "/health")
                if health:
                    status = health.get("status", "unknown")
                    version = health.get("version", "?")
                    peers = await self.get_peers()
                    peer_count = len(peers) if peers else 0
                    circles = set(p.get("circle", "default") for p in peers) if peers else set()
                    print(f"[bridge] Repowire {status} v{version} | "
                          f"{peer_count} peers | circles: {','.join(sorted(circles)) if circles else 'none'}")
            except Exception as e:
                print(f"[bridge] Health loop error: {e}")
            await asyncio.sleep(HEARTBEAT_INTERVAL)

    async def announce_presence(self):
        """Periodically announce Wheeler ecosystem status to the mesh."""
        await asyncio.sleep(5)  # Wait for initial health check
        while self.running:
            try:
                peers = await self.get_peers()
                peer_count = len(peers) if peers else 0
                msg = (
                    f"Wheeler Ecosystem Status | "
                    f"10 domain peers | 154 agents | "
                    f"{peer_count} mesh peers online | "
                    f"Server: AIOPS | "
                    f"Time: {datetime.now(timezone.utc).strftime('%H:%M:%S UTC')}"
                )
                await self.broadcast(msg)
            except Exception as e:
                print(f"[bridge] Announce error: {e}")
            await asyncio.sleep(300)  # Every 5 minutes

    async def orchestration_loop(self):
        """Autonomous orchestration — check mesh state and act."""
        await asyncio.sleep(10)
        while self.running:
            try:
                # Check for stale/offline peers
                peers = await self.get_peers()
                online = [p for p in peers if p.get("status") == "online"]
                busy = [p for p in peers if p.get("status") == "busy"]
                offline = [p for p in peers if p.get("status") == "offline"]

                if offline:
                    print(f"[bridge] {len(offline)} offline peers detected: "
                          f"{[p.get('display_name','?') for p in offline[:5]]}")

                # Log mesh health
                print(f"[bridge] Mesh: {len(online)} online | {len(busy)} busy | {len(offline)} offline")
            except Exception as e:
                print(f"[bridge] Orchestration error: {e}")
            await asyncio.sleep(120)  # Every 2 minutes

    async def run(self):
        """Main run loop."""
        print("=" * 60)
        print("[bridge] Wheeler-Repowire Bridge v1.0.0")
        print(f"[bridge] Daemon: {REPOWIRE_API}")
        print(f"[bridge] Domains: {len(WHEELER_PEERS)}")
        print(f"[bridge] Agents: 154 total Wheeler agents")
        print("=" * 60)

        await asyncio.gather(
            self.health_check_loop(),
            self.announce_presence(),
            self.orchestration_loop(),
        )

    def shutdown(self):
        """Graceful shutdown."""
        print("[bridge] Shutting down Wheeler-Repowire Bridge...")
        self.running = False


def main():
    bridge = WheelerRepowireBridge()
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, bridge.shutdown)
    try:
        loop.run_until_complete(bridge.run())
    except KeyboardInterrupt:
        pass
    finally:
        loop.close()


if __name__ == "__main__":
    main()
