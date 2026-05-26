#!/usr/bin/env python3
"""Wheeler Memory Sync — records PM2, Docker, and API health to PostgreSQL episodic_memory."""
import subprocess, sys, json, os, urllib.request
from datetime import datetime, timezone

NOW = datetime.now(timezone.utc).isoformat()

def pg_exec(sql):
    try:
        subprocess.run(
            ["docker", "exec", "frgops-standby", "psql", "-U", "frgops", "-d", "frgcrm",
             "-c", sql],
            capture_output=True, text=True, timeout=15
        )
    except Exception:
        pass

def pg_count(table):
    try:
        r = subprocess.run(
            ["docker", "exec", "frgops-standby", "psql", "-U", "frgops", "-d", "frgcrm",
             "-t", "-A", "-c", f"SELECT count(*) FROM {table}"],
            capture_output=True, text=True, timeout=15
        )
        return int(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip().isdigit() else 0
    except Exception:
        return 0

def record(event_type, source_agent, summary, importance=3):
    safe = summary.replace("'", "''")
    pg_exec(f"INSERT INTO episodic_memory (event_type, source_agent, summary, importance, created_at) "
            f"VALUES ('{event_type}', '{source_agent}', '{safe}', {importance}, '{NOW}')")

print(f"[memory-sync] {NOW} Starting sync...")

# PM2 snapshot
try:
    r = subprocess.run(["pm2", "jlist"], capture_output=True, text=True, timeout=10)
    pm2 = json.loads(r.stdout) if r.returncode == 0 else []
    online = sum(1 for p in pm2 if p.get("pm2_env", {}).get("status") == "online")
    total = len(pm2)
    record("pm2_snapshot", "memory-sync", f"PM2 fleet: {online}/{total} online", importance=2)
    print(f"  PM2: {online}/{total} online")
except Exception as e:
    print(f"  PM2 scan failed: {e}")

# Docker snapshot
try:
    r = subprocess.run(["docker", "ps", "--format", "{{.Names}}\t{{.Status}}"],
                       capture_output=True, text=True, timeout=10)
    containers = r.stdout.strip().split('\n') if r.stdout.strip() else []
    healthy = sum(1 for c in containers if "(healthy)" in c)
    unhealthy = sum(1 for c in containers if "(unhealthy)" in c)
    record("docker_snapshot", "memory-sync",
           f"Docker: {len(containers)} total, {healthy} healthy, {unhealthy} unhealthy", importance=2)
    print(f"  Docker: {healthy}/{len(containers)} healthy")
    for c in containers:
        if "(unhealthy)" in c:
            record("docker_alert", "memory-sync", f"Unhealthy: {c.split(chr(9))[0]}", importance=5)
except Exception as e:
    print(f"  Docker scan failed: {e}")

# API health
apis = {"brain": "8160", "dashboard": "8180", "embedding": "8191"}
for name, port in apis.items():
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{port}/health")
        resp = urllib.request.urlopen(req, timeout=5)
        if resp.status == 200:
            print(f"  API {name}: HTTP 200")
        else:
            record("api_alert", "memory-sync", f"API {name} returned HTTP {resp.status}", importance=4)
    except Exception:
        record("api_alert", "memory-sync", f"API {name} unreachable", importance=5)
        print(f"  API {name}: unreachable")

# Neo4j
try:
    r = subprocess.run(
        ["docker", "exec", "ecosystem-graph", "cypher-shell", "-u", "neo4j",
         "-p", "WheelerBrainOS-Graph-2026!-Neo4j-Root", "MATCH (n) RETURN count(n) AS total"],
        capture_output=True, text=True, timeout=10
    )
    for line in r.stdout.split('\n'):
        if line.strip().isdigit():
            print(f"  Neo4j: {line.strip()} nodes")
            break
except Exception as e:
    print(f"  Neo4j check failed: {e}")

# Table stats
for tbl in ["episodic_memory", "semantic_memory", "deployment_memory", "operational_memory"]:
    cnt = pg_count(tbl)
    print(f"  {tbl}: {cnt}")

print(f"[memory-sync] {NOW} Complete")
