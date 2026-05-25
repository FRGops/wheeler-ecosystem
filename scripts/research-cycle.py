#!/usr/bin/env python3
"""Wheeler Autonomous Research Cycle — daily intelligence gathering and memory recording."""
import json
import subprocess
import sys
import os
import urllib.request
from datetime import datetime, timezone

DB = "frgcrm"
USER = "frgops"

def pg_query(query: str):
    r = subprocess.run(
        ["docker", "exec", "frgops-standby", "psql", "-U", USER, "-d", DB,
         "-t", "-A", "-c", query],
        capture_output=True, text=True, timeout=30
    )
    return r.stdout.strip() if r.returncode == 0 else ""

def record_event(event_type, source, summary, entities=None, importance=3):
    entities_json = json.dumps(entities or [])
    summary_escaped = summary.replace("'", "''")
    pg_query(f"""
    INSERT INTO episodic_memory (event_type, source_agent, summary, entities, importance)
    VALUES ('{event_type}', '{source}', '{summary_escaped}', '{entities_json}', {importance})
    """)
    print(f"  [memory] {event_type}: {summary[:80]}")

def generate_embedding(text: str) -> list:
    """Generate embedding via local embedding service (all-MiniLM-L6-v2, 384-dim)."""
    try:
        data = json.dumps({
            "model": "local-embedding",
            "input": text[:8000]
        }).encode()
        req = urllib.request.Request(
            "http://127.0.0.1:8191/v1/embeddings",
            data=data,
            headers={"Content-Type": "application/json"}
        )
        resp = urllib.request.urlopen(req, timeout=30)
        result = json.loads(resp.read())
        emb = result.get("data", [{}])[0].get("embedding", [])
        if emb:
            return emb
    except Exception as e:
        print(f"  [embed] Failed: {e}")
    return []

def store_embedding(source_type, source_id, content, embedding):
    if not embedding:
        return
    emb_str = "[" + ",".join(str(x) for x in embedding) + "]"
    content_escaped = content.replace("'", "''")[:4000]
    pg_query(f"""
    INSERT INTO vector_embeddings (source_type, source_id, content, embedding)
    VALUES ('{source_type}', '{source_id}', '{content_escaped}', '{emb_str}'::vector)
    """)
    print(f"  [vector] Stored {len(embedding)}-dim embedding for {source_type}/{source_id}")

# ═══════════════════════════════════════════════════════════════════════════════
# RESEARCH PHASES
# ═══════════════════════════════════════════════════════════════════════════════

def phase_ecosystem_health():
    """Phase 1: Capture current ecosystem state."""
    print("\n── Phase 1: Ecosystem Health ──")

    # PM2 health
    try:
        result = subprocess.run(["pm2", "jlist"], capture_output=True, text=True, timeout=15)
        procs = json.loads(result.stdout)
        online = sum(1 for p in procs if p.get("pm2_env", {}).get("status") == "online")
        health_pct = round(online / max(len(procs), 1) * 100, 1)
        record_event("research_health", "research-automation",
                     f"Ecosystem health: {online}/{len(procs)} PM2 online ({health_pct}%)",
                     [{"online": online, "total": len(procs), "health_pct": health_pct}],
                     importance=5)

        # Embed the health summary
        summary = f"Wheeler ecosystem health at {datetime.now(timezone.utc).isoformat()}: {online}/{len(procs)} processes online, {health_pct}% healthy."
        store_embedding("ecosystem_health", f"health-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M')}",
                       summary, generate_embedding(summary))
    except Exception as e:
        print(f"  [error] PM2 health check failed: {e}")

def phase_docker_intelligence():
    """Phase 2: Docker container intelligence."""
    print("\n── Phase 2: Docker Intelligence ──")
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}"],
            capture_output=True, text=True, timeout=10
        )
        containers = []
        unhealthy = []
        for line in result.stdout.strip().split('\n'):
            if '\t' in line:
                name, image, status = line.split('\t', 2)
                healthy = "(healthy)" in status
                containers.append({"name": name, "image": image, "healthy": healthy})
                if not healthy and "Up" in status:
                    unhealthy.append(name)

        record_event("research_docker", "research-automation",
                     f"Docker: {len(containers)} containers, {sum(1 for c in containers if c['healthy'])} healthy, {len(unhealthy)} unhealthy",
                     containers,
                     importance=6 if unhealthy else 3)

        if unhealthy:
            store_embedding("docker_alert", f"unhealthy-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M')}",
                          f"Unhealthy containers: {', '.join(unhealthy)}",
                          generate_embedding(f"Unhealthy Docker containers detected: {', '.join(unhealthy)}"))
    except Exception as e:
        print(f"  [error] Docker scan failed: {e}")

def phase_graph_intelligence():
    """Phase 3: Knowledge graph analysis."""
    print("\n── Phase 3: Knowledge Graph Intelligence ──")
    try:
        result = subprocess.run(
            ["curl", "-s", "http://127.0.0.1:8160/api/v1/graph/summary"],
            capture_output=True, text=True, timeout=10
        )
        data = json.loads(result.stdout)

        neo4j = data.get("neo4j", {})
        nodes = neo4j.get("nodes", 0)
        rels = neo4j.get("relationships", 0)

        record_event("research_graph", "research-automation",
                     f"Knowledge graph: {nodes} nodes, {rels} relationships",
                     [{"nodes": nodes, "relationships": rels}],
                     importance=4)

        # Get domain intelligence
        result2 = subprocess.run(
            ["curl", "-s", "http://127.0.0.1:8160/api/v1/graph/domains"],
            capture_output=True, text=True, timeout=10
        )
        domains = json.loads(result2.stdout).get("domains", [])
        if domains:
            domain_summary = "Intelligence domains: " + ", ".join(
                f"{d['domain']}({d['agent_count']})" for d in domains[:5]
            )
            store_embedding("graph_intel", f"domains-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M')}",
                          domain_summary, generate_embedding(domain_summary))
    except Exception as e:
        print(f"  [error] Graph analysis failed: {e}")

def phase_memory_synthesis():
    """Phase 4: Analyze recent memories for patterns."""
    print("\n── Phase 4: Memory Synthesis ──")
    try:
        rows = pg_query(
            "SELECT event_type, count(*), max(created_at) FROM episodic_memory "
            "WHERE created_at > now() - interval '24 hours' GROUP BY event_type ORDER BY count(*) DESC"
        )
        if rows:
            pattern_summary = "24h memory patterns: " + "; ".join(
                r.split("|")[0] + "=" + r.split("|")[1] for r in rows.split("\n")[:5] if r
            )
            record_event("research_synthesis", "research-automation",
                        pattern_summary, importance=3)
    except Exception as e:
        print(f"  [error] Memory synthesis failed: {e}")

def phase_competitor_watch():
    """Phase 5: Competitor intelligence (from ChangeDetection or web sources)."""
    print("\n── Phase 5: Competitor Watch ──")
    try:
        # Check ChangeDetection for recent changes
        req = urllib.request.Request(
            "http://127.0.0.1:5000/api/v1/watch?tags=competitors",
            headers={"X-API-Key": os.environ.get("CHANGEDETECTION_API_KEY", "")}
        )
        resp = urllib.request.urlopen(req, timeout=10)
        data = json.loads(resp.read())
        record_event("research_competitor", "research-automation",
                    f"Competitor watch executed: {len(data) if isinstance(data, list) else 'data received'}",
                    importance=4)
    except urllib.error.HTTPError as e:
        if e.code == 401 or e.code == 403:
            record_event("research_competitor", "research-automation",
                        "Competitor watch: ChangeDetection API key not configured", importance=2)
        else:
            record_event("research_competitor", "research-automation",
                        f"Competitor watch error: HTTP {e.code}", importance=5)
    except Exception as e:
        record_event("research_competitor", "research-automation",
                    f"Competitor watch unavailable: {str(e)[:100]}", importance=3)

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    ts = datetime.now(timezone.utc).isoformat()
    print(f"╔══ Wheeler Research Cycle ══╗")
    print(f"║ {ts}")
    print(f"╚{'═'*30}╝")

    phases = [
        phase_ecosystem_health,
        phase_docker_intelligence,
        phase_graph_intelligence,
        phase_memory_synthesis,
        phase_competitor_watch,
    ]

    for phase in phases:
        try:
            phase()
        except Exception as e:
            print(f"  [FATAL] {phase.__name__}: {e}")

    # Final stats
    count = pg_query("SELECT count(*) FROM episodic_memory")
    vec_count = pg_query("SELECT count(*) FROM vector_embeddings")
    print(f"\n═══ Cycle Complete ═══")
    print(f"  episodic_memories: {count}")
    print(f"  vector_embeddings: {vec_count}")
    print(f"  timestamp: {ts}")
