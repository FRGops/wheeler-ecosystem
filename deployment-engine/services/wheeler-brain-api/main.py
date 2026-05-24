"""Wheeler Brain Enterprise API — Agent fleet intelligence and command interface."""
import os
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="Wheeler Brain Enterprise API", version="1.0.0")

NEO4J_URI = os.getenv("NEO4J_URI", "bolt://127.0.0.1:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "")

# ── Models ──────────────────────────────────────────────────────────────────

class CommandRequest(BaseModel):
    agent: str
    action: str
    params: dict = {}

class AgentStatus(BaseModel):
    name: str
    status: str
    uptime: float
    restarts: int
    memory_mb: float
    cpu_pct: float

class EcosystemSummary(BaseModel):
    total_agents: int
    agents_online: int
    total_services: int
    services_healthy: int
    total_docker_containers: int
    health_score: float
    timestamp: str

# ── PM2 Integration ─────────────────────────────────────────────────────────

def _pm2_jlist():
    """Get raw PM2 process list."""
    try:
        result = subprocess.run(
            ["pm2", "jlist"], capture_output=True, text=True, timeout=10,
            env={**os.environ, "PM2_HOME": os.environ.get("PM2_HOME", "/root/.pm2")}
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception:
        pass
    return []

def _pm2_start(process_name: str):
    """Start a PM2 process by name."""
    try:
        subprocess.run(["pm2", "start", process_name], capture_output=True, text=True, timeout=30)
        return True
    except Exception:
        return False

def _pm2_restart(process_name: str):
    """Restart a PM2 process by name."""
    try:
        subprocess.run(["pm2", "restart", process_name], capture_output=True, text=True, timeout=30)
        return True
    except Exception:
        return False

# ── Neo4j Integration ───────────────────────────────────────────────────────

def _neo4j_available() -> bool:
    try:
        from neo4j import GraphDatabase
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
        with driver.session() as session:
            session.run("RETURN 1")
        driver.close()
        return True
    except Exception:
        return False

def _neo4j_graph_summary() -> dict:
    try:
        from neo4j import GraphDatabase
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
        with driver.session() as session:
            node_count = session.run("MATCH (n) RETURN count(n) AS c").single()["c"]
            rel_count = session.run("MATCH ()-[r]->() RETURN count(r) AS c").single()["c"]
            labels = [r["label"] for r in session.run("CALL db.labels()")]
        driver.close()
        return {"nodes": node_count, "relationships": rel_count, "labels": labels, "status": "connected"}
    except Exception:
        return {"nodes": 0, "relationships": 0, "labels": [], "status": "disconnected"}

# ── Endpoints ───────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "wheeler-brain-api",
        "neo4j": "connected" if _neo4j_available() else "degraded",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/agents")
async def get_agents():
    processes = _pm2_jlist()
    agents = []
    for p in processes:
        env = p.get("pm2_env", {})
        agents.append(AgentStatus(
            name=p.get("name", "unknown"),
            status=env.get("status", "unknown"),
            uptime=env.get("pm_uptime", 0) / 1000.0 if env.get("pm_uptime") else 0,
            restarts=env.get("restart_time", 0),
            memory_mb=round(p.get("monit", {}).get("memory", 0) / 1048576, 1),
            cpu_pct=round(p.get("monit", {}).get("cpu", 0), 1)
        ).model_dump())

    online = sum(1 for a in agents if a["status"] == "online")
    return {
        "agents": agents,
        "total": len(agents),
        "online": online,
        "degraded": len(agents) - online,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/ecosystem")
async def ecosystem_summary():
    agents = _pm2_jlist()
    online = sum(1 for p in agents if p.get("pm2_env", {}).get("status") == "online")

    try:
        docker_count = int(subprocess.run(
            ["docker", "ps", "-q"], capture_output=True, text=True, timeout=10
        ).stdout.strip().count('\n') + 1)
    except Exception:
        docker_count = 0

    score = (online / max(len(agents), 1)) * 100.0

    return EcosystemSummary(
        total_agents=len(agents),
        agents_online=online,
        total_services=len(agents),
        services_healthy=online,
        total_docker_containers=docker_count,
        health_score=round(score, 1),
        timestamp=datetime.now(timezone.utc).isoformat()
    ).model_dump()

@app.post("/api/v1/command")
async def execute_command(req: CommandRequest):
    action = req.action
    agent = req.agent

    if action == "restart":
        success = _pm2_restart(agent)
        return {"agent": agent, "action": "restart", "success": success}
    elif action == "start":
        success = _pm2_start(agent)
        return {"agent": agent, "action": "start", "success": success}
    elif action == "status":
        agents = _pm2_jlist()
        match = next((p for p in agents if p.get("name") == agent), None)
        if match:
            env = match.get("pm2_env", {})
            return {"agent": agent, "status": env.get("status"), "uptime": env.get("pm_uptime", 0) / 1000.0, "restarts": env.get("restart_time", 0)}
        raise HTTPException(status_code=404, detail=f"Agent {agent} not found")
    else:
        raise HTTPException(status_code=400, detail=f"Unknown action: {action}")

@app.get("/api/v1/intelligence/feed")
async def intelligence_feed(limit: int = 10):
    agents = _pm2_jlist()
    feed = []
    for p in agents[:limit]:
        env = p.get("pm2_env", {})
        feed.append({
            "agent": p.get("name"),
            "status": env.get("status"),
            "uptime_seconds": round(env.get("pm_uptime", 0) / 1000.0, 1) if env.get("pm_uptime") else 0,
            "restarts": env.get("restart_time", 0),
            "observation_time": datetime.now(timezone.utc).isoformat()
        })
    return {"feed": feed, "count": len(feed), "timestamp": datetime.now(timezone.utc).isoformat()}

@app.get("/api/v1/graph/summary")
async def graph_summary():
    neo4j_data = _neo4j_graph_summary()
    agents = _pm2_jlist()

    graph = {
        "neo4j": neo4j_data,
        "pm2_agents": len(agents),
        "pm2_online": sum(1 for p in agents if p.get("pm2_env", {}).get("status") == "online"),
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    return graph

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8160, log_level="info")
