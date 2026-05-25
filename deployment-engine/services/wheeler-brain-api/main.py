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

# ── PostgreSQL Memory Integration ─────────────────────────────────────────────

def _pg_query(query: str):
    """Execute a query against PostgreSQL :5433 memory layer."""
    try:
        result = subprocess.run(
            ["docker", "exec", "frgops-standby", "psql", "-U", "frgops", "-d", "frgcrm",
             "-t", "-A", "-c", query],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode != 0:
            return {"error": result.stderr.strip()}
        return [line for line in result.stdout.strip().split('\n') if line]
    except Exception as e:
        return {"error": str(e)}

def _pg_query_json(query: str):
    """Execute a query and return results as list of dicts."""
    try:
        result = subprocess.run(
            ["docker", "exec", "frgops-standby", "psql", "-U", "frgops", "-d", "frgcrm",
             "-t", "-A", "-F", "|", "-c", query],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode != 0:
            return []
        lines = [l for l in result.stdout.strip().split('\n') if l]
        return lines
    except Exception:
        return []

# ── Intelligence Memory Endpoints ─────────────────────────────────────────────

class MemoryQuery(BaseModel):
    query: str
    limit: int = 10

@app.get("/api/v1/memory/recent")
async def memory_recent(limit: int = 20, event_type: str = None):
    """Get recent episodic memories with optional type filter."""
    type_clause = f"WHERE event_type = '{event_type}'" if event_type else ""
    rows = _pg_query_json(
        f"SELECT id, event_type, source_agent, summary, importance, created_at "
        f"FROM episodic_memory {type_clause} ORDER BY created_at DESC LIMIT {limit}"
    )
    return {"memories": rows, "count": len(rows), "timestamp": datetime.now(timezone.utc).isoformat()}

@app.get("/api/v1/memory/stats")
async def memory_stats():
    """Statistics across all memory tables."""
    stats = {}
    for table in ["episodic_memory", "semantic_memory", "deployment_memory", "operational_memory"]:
        rows = _pg_query(f"SELECT count(*) FROM {table}")
        stats[table] = int(rows[0]) if rows and not isinstance(rows, dict) else 0

    # Event type breakdown
    breakdown = _pg_query_json(
        "SELECT event_type, count(*) FROM episodic_memory GROUP BY event_type ORDER BY count(*) DESC"
    )
    return {
        "tables": stats,
        "event_breakdown": breakdown,
        "total_memories": sum(stats.values()),
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.post("/api/v1/memory/query")
async def memory_query(req: MemoryQuery):
    """Execute a parameterized query against the memory layer. For complex agent queries."""
    safe_keywords = ["SELECT", "COUNT", "FROM", "WHERE", "GROUP", "ORDER", "LIMIT", "AND", "OR", "BY", "DESC", "ASC"]
    query_upper = req.query.upper()
    if not any(kw in query_upper for kw in safe_keywords[:3]):
        raise HTTPException(status_code=400, detail="Query must be a SELECT statement")

    if any(dangerous in query_upper for dangerous in ["DROP", "DELETE", "UPDATE", "INSERT", "ALTER", "CREATE"]):
        raise HTTPException(status_code=400, detail="Write operations not allowed via query endpoint")

    rows = _pg_query_json(f"{req.query} LIMIT {req.limit}")
    return {"results": rows, "count": len(rows), "timestamp": datetime.now(timezone.utc).isoformat()}

# ── Intelligence Graph Endpoints ──────────────────────────────────────────────

class GraphQuery(BaseModel):
    cypher: str
    limit: int = 50

@app.post("/api/v1/graph/query")
async def graph_query(req: GraphQuery):
    """Execute a Cypher query against Neo4j knowledge graph."""
    try:
        from neo4j import GraphDatabase
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
        results = []
        with driver.session() as session:
            r = session.run(req.cypher)
            for record in r:
                results.append(dict(record))
        driver.close()
        return {"results": results[:req.limit], "count": len(results[:req.limit]),
                "timestamp": datetime.now(timezone.utc).isoformat()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Graph query failed: {str(e)}")

@app.get("/api/v1/graph/agents")
async def graph_agents(domain: str = None):
    """List registered agents from Neo4j, optionally filtered by domain."""
    if domain:
        cypher = f"""
        MATCH (a:ClaudeAgent)-[:BELONGS_TO]->(d:Domain {{name: '{domain}'}})
        RETURN a.name AS name, d.name AS domain, a.status AS status
        """
    else:
        cypher = """
        MATCH (a:ClaudeAgent)
        OPTIONAL MATCH (a)-[:BELONGS_TO]->(d:Domain)
        RETURN a.name AS name, d.name AS domain, a.status AS status
        ORDER BY domain, name
        """
    try:
        from neo4j import GraphDatabase
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
        results = []
        with driver.session() as session:
            for record in session.run(cypher):
                results.append({"name": record.get("name"), "domain": record.get("domain"),
                                "status": record.get("status")})
        driver.close()

        domains = list(set(r["domain"] for r in results if r["domain"]))
        return {"agents": results, "total": len(results), "domains": domains,
                "timestamp": datetime.now(timezone.utc).isoformat()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Agent query failed: {str(e)}")

@app.get("/api/v1/graph/domains")
async def graph_domains():
    """List all intelligence domains and their agent counts."""
    cypher = """
    MATCH (d:Domain)<-[:BELONGS_TO]-(a:ClaudeAgent)
    RETURN d.name AS domain, count(a) AS agent_count
    ORDER BY agent_count DESC
    """
    try:
        from neo4j import GraphDatabase
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
        results = []
        with driver.session() as session:
            for record in session.run(cypher):
                results.append({"domain": record.get("domain"), "agent_count": record.get("agent_count")})
        driver.close()
        return {"domains": results, "total_domains": len(results),
                "timestamp": datetime.now(timezone.utc).isoformat()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Domain query failed: {str(e)}")

# ── Hybrid Intelligence Search ────────────────────────────────────────────────

class SearchQuery(BaseModel):
    q: str
    limit: int = 10

@app.post("/api/v1/intelligence/search")
async def intelligence_search(req: SearchQuery):
    """Hybrid search across graph + memory + PM2 for the given query string."""
    results = {"graph": [], "memory": [], "pm2": [], "query": req.q}

    # Graph search: find agents matching name
    try:
        from neo4j import GraphDatabase
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
        with driver.session() as session:
            r = session.run(
                "MATCH (a:ClaudeAgent) WHERE a.name CONTAINS $q "
                "RETURN a.name AS name, labels(a) AS type LIMIT $limit",
                {"q": req.q, "limit": req.limit}
            )
            results["graph"] = [dict(record) for record in r]
        driver.close()
    except Exception:
        pass

    # Memory search: search summaries
    rows = _pg_query_json(
        f"SELECT id, event_type, source_agent, summary FROM episodic_memory "
        f"WHERE summary ILIKE '%{req.q}%' ORDER BY created_at DESC LIMIT {req.limit}"
    )
    results["memory"] = [{"id": r.split("|")[0], "event_type": r.split("|")[1] if "|" in r else "",
                          "agent": r.split("|")[2] if len(r.split("|")) > 1 else "",
                          "summary": "|".join(r.split("|")[3:]) if r.count("|") >= 3 else r}
                         for r in rows] if rows else []

    # PM2 search: find running processes matching name
    agents = _pm2_jlist()
    results["pm2"] = [{"name": p.get("name"), "status": p.get("pm2_env", {}).get("status")}
                      for p in agents if req.q.lower() in p.get("name", "").lower()][:req.limit]

    results["total_hits"] = len(results["graph"]) + len(results["memory"]) + len(results["pm2"])
    results["timestamp"] = datetime.now(timezone.utc).isoformat()
    return results


# ═══════════════════════════════════════════════════════════════
# QDRANT INTEGRATION — COREDB (100.118.166.117:6333)
# ═══════════════════════════════════════════════════════════════

QDRANT_URL = os.getenv("QDRANT_URL", "http://100.118.166.117:6333")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY", "WheelerBrainOS-Qdrant-2026!")
QDRANT_COLLECTION = "wheeler_memory"

def _qdrant(method: str, path: str, body: dict = None) -> dict:
    """Make an API call to Qdrant on COREDB."""
    try:
        import urllib.request
        url = f"{QDRANT_URL}{path}"
        data = json.dumps(body).encode() if body else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("api-key", QDRANT_API_KEY)
        if data:
            req.add_header("Content-Type", "application/json")
        resp = urllib.request.urlopen(req, timeout=10)
        return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def _get_embedding(text: str) -> list:
    """Get embedding from local embedding service."""
    try:
        import urllib.request
        data = json.dumps({"input": text, "model": "local"}).encode()
        req = urllib.request.Request("http://127.0.0.1:8191/v1/embeddings", data=data,
                                     headers={"Content-Type": "application/json"})
        resp = json.loads(urllib.request.urlopen(req, timeout=10).read())
        return resp["data"][0]["embedding"]
    except Exception:
        return []

class VectorSearchRequest(BaseModel):
    query: str
    limit: int = 10
    collection: str = QDRANT_COLLECTION

@app.post("/api/v1/intelligence/vector-search")
async def vector_search(req: VectorSearchRequest):
    """Semantic vector search via Qdrant on COREDB + local embeddings."""
    embedding = _get_embedding(req.query)
    if not embedding:
        raise HTTPException(status_code=503, detail="Embedding service unavailable")

    results = _qdrant("POST", f"/collections/{req.collection}/points/search",
                      {"vector": embedding, "limit": req.limit, "with_payload": True})

    hits = []
    for r in results.get("result", []):
        hits.append({
            "id": r.get("id"),
            "score": round(r.get("score", 0), 4),
            "payload": r.get("payload", {})
        })

    return {
        "query": req.query,
        "collection": req.collection,
        "hits": hits,
        "total": len(hits),
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/intelligence/qdrant/health")
async def qdrant_health():
    """Check Qdrant health on COREDB."""
    info = _qdrant("GET", "/readyz")
    collections = _qdrant("GET", "/collections")
    return {
        "qdrant": "reachable" if "ready" in str(info).lower() or info.get("result") else "degraded",
        "collections": [c.get("name") for c in collections.get("result", {}).get("collections", [])],
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8160, log_level="info")
