#!/usr/bin/env python3
"""
Wheeler-Repowire Bridge v2.0 — Persistent WebSocket sessions for all domain peers.

Each of the 10 Wheeler domain peers maintains a persistent WebSocket connection
to the repowire daemon (:8377). This enables real-time P2P conversational
communication: any peer can send direct asks, notifications, and queries to
any Wheeler domain peer, and the bridge routes incoming messages to handlers.

Architecture v2:
    Wheeler Agents ←→ HTTP API ←→ Repowire Daemon (:8377) ←→ WebSocket Mesh
         ↑                               ↑
         |  10 persistent WS sessions    |  ask/notify/broadcast
         └──── DomainPeer instances ─────┘  incoming messages
"""

import asyncio
import json
import os
import signal
import sys
from datetime import datetime, timezone

import httpx
import websockets
from websockets.asyncio.client import ClientConnection

REPOWIRE_WS = "ws://127.0.0.1:8377/ws"
REPOWIRE_API = "http://127.0.0.1:8377"
HEARTBEAT_INTERVAL = 30
RECONNECT_BASE_DELAY = 2
RECONNECT_MAX_DELAY = 120

WHEELER_PEERS = {
    "wheeler-orchestrator": {
        "display_name": "Wheeler-Orchestrator",
        "circle": "wheeler-core",
        "role": "orchestrator",
        "role_desc": "Master Orchestrator — 154 agents, cross-domain coordination",
    },
    "wheeler-infra": {
        "display_name": "Wheeler-Infra",
        "circle": "wheeler-ops",
        "role": "agent",
        "role_desc": "Docker, PM2, networking, UFW, system health",
    },
    "wheeler-security": {
        "display_name": "Wheeler-Security",
        "circle": "wheeler-ops",
        "role": "agent",
        "role_desc": "Secrets, UFW, SSL, CVE, threat intelligence",
    },
    "wheeler-deploy": {
        "display_name": "Wheeler-Deploy",
        "circle": "wheeler-ops",
        "role": "agent",
        "role_desc": "7-gate pipeline, pre-flight, rollback",
    },
    "wheeler-financial": {
        "display_name": "Wheeler-Financial",
        "circle": "wheeler-finance",
        "role": "agent",
        "role_desc": "P&L, revenue, Stripe, treasury, cost",
    },
    "wheeler-db": {
        "display_name": "Wheeler-DB",
        "circle": "wheeler-ops",
        "role": "agent",
        "role_desc": "PostgreSQL, backups, replication, queries",
    },
    "wheeler-monitoring": {
        "display_name": "Wheeler-Monitoring",
        "circle": "wheeler-ops",
        "role": "agent",
        "role_desc": "Prometheus, Loki, Grafana, alerts",
    },
    "wheeler-growth": {
        "display_name": "Wheeler-Growth",
        "circle": "wheeler-growth",
        "role": "agent",
        "role_desc": "SEO, content, distribution, conversion",
    },
    "wheeler-compliance": {
        "display_name": "Wheeler-Compliance",
        "circle": "wheeler-legal",
        "role": "agent",
        "role_desc": "TCPA, CCPA, FCRA, surplus funds, state laws",
    },
    "wheeler-revenue": {
        "display_name": "Wheeler-Revenue",
        "circle": "wheeler-finance",
        "role": "agent",
        "role_desc": "MRR/ARR, Stripe, churn, subscriptions",
    },
}


class DomainPeer:
    """A persistent WebSocket connection representing one Wheeler domain peer."""

    def __init__(self, peer_id: str, config: dict, bridge: "WheelerRepowireBridge"):
        self.peer_id = peer_id
        self.config = config
        self.bridge = bridge
        self.ws: ClientConnection | None = None
        self.session_id: str | None = None
        self.reconnect_delay = RECONNECT_BASE_DELAY
        self.connected = False
        self.message_count = 0

    @property
    def display_name(self) -> str:
        return self.config["display_name"]

    @property
    def circle(self) -> str:
        return self.config["circle"]

    async def connect(self):
        """Establish WebSocket connection and register as a peer."""
        try:
            self.ws = await websockets.connect(
                REPOWIRE_WS, ping_interval=30, ping_timeout=10, close_timeout=5
            )
            connect_msg = {
                "type": "connect",
                "display_name": self.display_name,
                "circle": self.circle,
                "backend": "claude-code",
                "path": "/root",
                "role": self.config.get("role", "agent"),
            }
            await self.ws.send(json.dumps(connect_msg))
            resp = await asyncio.wait_for(self.ws.recv(), timeout=10)
            data = json.loads(resp)

            if data.get("type") == "connected":
                self.session_id = data.get("session_id", "unknown")
                self.connected = True
                self.reconnect_delay = RECONNECT_BASE_DELAY
                # Rename to our canonical Wheeler display name
                await self.ws.send(json.dumps({
                    "type": "update_display_name",
                    "display_name": self.display_name,
                }))
                await asyncio.sleep(0.3)
                await self.ws.send(json.dumps({"type": "status", "status": "online"}))
                print(f"[peer:{self.peer_id}] CONNECTED as {self.display_name} "
                      f"(session={self.session_id[:30]}..., circle={self.circle})")
                return True
            else:
                print(f"[peer:{self.peer_id}] Unexpected connect response: {data}")
                await self.ws.close()
                return False

        except Exception as e:
            print(f"[peer:{self.peer_id}] Connect failed: {e}")
            self.connected = False
            return False

    async def listen(self):
        """Listen for incoming messages on the WebSocket."""
        if not self.ws or not self.connected:
            return
        try:
            async for raw in self.ws:
                try:
                    msg = json.loads(raw)
                    await self._handle_message(msg)
                except json.JSONDecodeError:
                    print(f"[peer:{self.peer_id}] Invalid JSON received")
        except websockets.exceptions.ConnectionClosed as e:
            print(f"[peer:{self.peer_id}] Connection closed: code={e.code}")
        except Exception as e:
            print(f"[peer:{self.peer_id}] Listen error: {e}")
        finally:
            self.connected = False

    async def _handle_message(self, msg: dict):
        """Route incoming message to appropriate handler."""
        msg_type = msg.get("type", "unknown")
        self.message_count += 1

        if msg_type == "ask":
            await self._on_ask(msg)
        elif msg_type == "notify":
            await self._on_notify(msg)
        elif msg_type == "broadcast":
            await self._on_broadcast(msg)
        elif msg_type == "query":
            await self._on_query(msg)
        elif msg_type == "ping":
            await self._send({"type": "pong"})
        else:
            print(f"[peer:{self.peer_id}] Unhandled message type: {msg_type}")

    async def _on_ask(self, msg: dict):
        """Handle an incoming ask — non-blocking request from another peer."""
        from_peer = msg.get("from_peer", "?")
        text = msg.get("text", "")
        corr_id = msg.get("correlation_id", "?")
        reply_to = msg.get("reply_to")
        print(f"[peer:{self.peer_id}] ASK from={from_peer}: {text[:150]}")
        if self.bridge.on_ask:
            await self.bridge.on_ask(self.peer_id, from_peer, text, corr_id, reply_to)

    async def _on_notify(self, msg: dict):
        """Handle an incoming notification — FYI, no response expected."""
        from_peer = msg.get("from_peer", "?")
        text = msg.get("text", "")
        print(f"[peer:{self.peer_id}] NOTIFY from={from_peer}: {text[:150]}")
        if self.bridge.on_notify:
            await self.bridge.on_notify(self.peer_id, from_peer, text)

    async def _on_broadcast(self, msg: dict):
        """Handle an incoming broadcast — message to all peers."""
        from_peer = msg.get("from_peer", "?")
        text = msg.get("text", "")
        if self.bridge.on_broadcast:
            await self.bridge.on_broadcast(self.peer_id, from_peer, text)

    async def _on_query(self, msg: dict):
        """Handle an incoming query — blocking RPC request expecting a response."""
        from_peer = msg.get("from_peer", "?")
        text = msg.get("text", "")
        corr_id = msg.get("correlation_id", "?")
        print(f"[peer:{self.peer_id}] QUERY from={from_peer}: {text[:150]}")
        if self.bridge.on_query:
            response_text = await self.bridge.on_query(self.peer_id, from_peer, text, corr_id)
            if response_text:
                await self._send({"type": "response", "correlation_id": corr_id, "text": response_text})
            else:
                await self._send({"type": "error", "correlation_id": corr_id, "error": "No handler available"})

    async def _send(self, data: dict):
        """Send a message through the WebSocket."""
        if self.ws and self.connected:
            try:
                await self.ws.send(json.dumps(data))
            except Exception as e:
                print(f"[peer:{self.peer_id}] Send error: {e}")

    async def heartbeat(self):
        """Send periodic status to keep the peer online."""
        if self.ws and self.connected:
            try:
                await self.ws.send(json.dumps({"type": "status", "status": "online"}))
            except Exception:
                self.connected = False

    async def run_forever(self):
        """Main loop: connect, listen, reconnect on failure."""
        while self.bridge.running:
            if await self.connect():
                await self.listen()
            if not self.bridge.running:
                break
            print(f"[peer:{self.peer_id}] Reconnecting in {self.reconnect_delay}s...")
            await asyncio.sleep(self.reconnect_delay)
            self.reconnect_delay = min(self.reconnect_delay * 2, RECONNECT_MAX_DELAY)

    async def close(self):
        """Gracefully close the WebSocket."""
        self.connected = False
        if self.ws:
            try:
                await self.ws.close()
            except Exception:
                pass


class WheelerRepowireBridge:
    """Manages all 10 domain peers, HTTP API access, and message routing."""

    def __init__(self):
        self.running = True
        self.client = httpx.AsyncClient(timeout=15, base_url=REPOWIRE_API)
        self.peers: dict[str, DomainPeer] = {}

        # Message handler callbacks — set externally to route to agents
        self.on_ask = None
        self.on_notify = None
        self.on_broadcast = None
        self.on_query = None

        for peer_id, config in WHEELER_PEERS.items():
            self.peers[peer_id] = DomainPeer(peer_id, config, self)

    # ── HTTP API wrappers ───────────────────────────────────────────

    async def _api(self, method: str, path: str, **kw) -> dict | None:
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
        result = await self._api("GET", "/peers")
        peers_list = result.get("peers", []) if isinstance(result, dict) else []
        return peers_list if isinstance(peers_list, list) else []

    async def notify_peer(self, target: str, text: str, from_peer: str = "wheeler-orchestrator") -> bool:
        result = await self._api("POST", "/notify", json={
            "to_peer": target, "text": text, "from_peer": from_peer,
        })
        return result is not None

    async def broadcast(self, text: str, from_peer: str = "wheeler-orchestrator") -> bool:
        result = await self._api("POST", "/broadcast", json={
            "from_peer": from_peer, "text": text,
        })
        return result is not None

    async def ask_peer(self, target: str, text: str, from_peer: str = "wheeler-orchestrator") -> dict | None:
        result = await self._api("POST", "/ask", json={
            "to_peer": target, "text": text, "from_peer": from_peer,
        })
        return result

    # ── Loops ───────────────────────────────────────────────────────

    async def health_check_loop(self):
        while self.running:
            try:
                health = await self._api("GET", "/health")
                if health:
                    status = health.get("status", "unknown")
                    version = health.get("version", "?")
                    peers = await self.get_peers()
                    peer_count = len(peers)
                    online_count = len([p for p in peers if p.get("status") == "online"])
                    offline_count = peer_count - online_count
                    persistent_count = len([p for p in self.peers.values() if p.connected])
                    circles = set(p.get("circle", "default") for p in peers)
                    print(f"[bridge] Repowire {status} v{version} | "
                          f"mesh: {peer_count} total ({online_count} online, {offline_count} offline) | "
                          f"persistent: {persistent_count}/{len(self.peers)} | "
                          f"circles: {','.join(sorted(circles)) if circles else 'none'}")
            except Exception as e:
                print(f"[bridge] Health loop error: {e}")
            await asyncio.sleep(HEARTBEAT_INTERVAL)

    async def heartbeat_loop(self):
        """Send periodic heartbeat to all connected peers."""
        while self.running:
            for peer in self.peers.values():
                if peer.connected:
                    await peer.heartbeat()
            await asyncio.sleep(HEARTBEAT_INTERVAL)

    async def announce_presence_loop(self):
        await asyncio.sleep(10)
        while self.running:
            try:
                persistent = len([p for p in self.peers.values() if p.connected])
                peers = await self.get_peers()
                msg = (
                    f"Wheeler Ecosystem Status | "
                    f"{persistent}/{len(self.peers)} domain peers online | "
                    f"{len(peers)} mesh peers total | "
                    f"Server: AIOPS | "
                    f"Time: {datetime.now(timezone.utc).strftime('%H:%M:%S UTC')}"
                )
                await self.broadcast(msg)
            except Exception as e:
                print(f"[bridge] Announce error: {e}")
            await asyncio.sleep(300)

    async def orchestration_loop(self):
        await asyncio.sleep(15)
        while self.running:
            try:
                peers = await self.get_peers()
                online = [p for p in peers if p.get("status") == "online"]
                offline = [p for p in peers if p.get("status") == "offline"]
                persistent = [pid for pid, p in self.peers.items() if p.connected]
                missing = [pid for pid, p in self.peers.items() if not p.connected]

                if offline:
                    names = [p.get('display_name', '?') for p in offline[:5]]
                    print(f"[bridge] {len(offline)} offline peers: {names}")
                if missing:
                    print(f"[bridge] {len(missing)} domain peers disconnected: {missing}")

                print(f"[bridge] Mesh: {len(online)} online | {len(offline)} offline | "
                      f"persistent: {len(persistent)}/{len(self.peers)}")
            except Exception as e:
                print(f"[bridge] Orchestration error: {e}")
            await asyncio.sleep(120)

    # ── Default message handlers ────────────────────────────────────

    async def default_on_ask(self, peer_id: str, from_peer: str, text: str, corr_id: str, reply_to: str | None):
        print(f"[bridge] ← ASK to {peer_id} from {from_peer}: {text[:200]}")

    async def default_on_notify(self, peer_id: str, from_peer: str, text: str):
        print(f"[bridge] ← NOTIFY to {peer_id} from {from_peer}: {text[:200]}")

    async def default_on_broadcast(self, peer_id: str, from_peer: str, text: str):
        pass  # Broadcasts are logged by individual peers, skip double-logging

    async def default_on_query(self, peer_id: str, from_peer: str, text: str, corr_id: str) -> str:
        return f"[{peer_id}] Received query. Status: online. {len(self.peers)} domain peers active."

    # ── Main run ────────────────────────────────────────────────────

    async def run(self):
        print("=" * 60)
        print("[bridge] Wheeler-Repowire Bridge v2.0.0")
        print(f"[bridge] Daemon WS: {REPOWIRE_WS}")
        print(f"[bridge] Daemon API: {REPOWIRE_API}")
        print(f"[bridge] Domain Peers: {len(self.peers)} persistent WebSocket sessions")
        print(f"[bridge] Mode: PERSISTENT P2P — all peers stay connected")
        print("=" * 60)

        self.on_ask = self.default_on_ask
        self.on_notify = self.default_on_notify
        self.on_broadcast = self.default_on_broadcast
        self.on_query = self.default_on_query

        # Start all peer connections + management loops
        tasks = [peer.run_forever() for peer in self.peers.values()]
        tasks += [
            self.health_check_loop(),
            self.heartbeat_loop(),
            self.announce_presence_loop(),
            self.orchestration_loop(),
        ]
        await asyncio.gather(*tasks)

    def shutdown(self):
        print("[bridge] Shutting down Wheeler-Repowire Bridge v2...")
        self.running = False
        for peer in self.peers.values():
            asyncio.ensure_future(peer.close())


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
