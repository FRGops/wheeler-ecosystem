#!/bin/bash
# Wheeler Daily Intelligence Brief — aggregates ecosystem state and writes to memory
set -euo pipefail

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DATE=$(date -u +%Y-%m-%d)
LOG="/var/log/wheeler-daily-brief.log"

echo "=== Wheeler Daily Brief — $TIMESTAMP ===" | tee -a "$LOG"

# PM2 snapshot
ONLINE=$(pm2 jlist 2>/dev/null | python3 -c "import json,sys; p=json.load(sys.stdin); print(sum(1 for x in p if x.get('pm2_env',{}).get('status')=='online'))" 2>/dev/null || echo "?")
TOTAL=$(pm2 jlist 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
echo "  PM2: $ONLINE/$TOTAL online" | tee -a "$LOG"

# Docker snapshot
DOCKER_TOTAL=$(docker ps -q | wc -l)
DOCKER_HEALTHY=$(docker ps --filter 'health=healthy' -q | wc -l)
DOCKER_UNHEALTHY=$(docker ps --filter 'health=unhealthy' -q | wc -l)
echo "  Docker: $DOCKER_TOTAL total, $DOCKER_HEALTHY healthy, $DOCKER_UNHEALTHY unhealthy" | tee -a "$LOG"

# Neo4j
NEO4J_NODES=$(docker exec ecosystem-graph cypher-shell -u neo4j -p 'WheelerBrainOS-Graph-2026!-Neo4j-Root' 'MATCH (n) RETURN count(n) AS c' 2>/dev/null | tail -1 | tr -d ' "') || NEO4J_NODES="?"
echo "  Neo4j: ${NEO4J_NODES:-?} nodes" | tee -a "$LOG"

# Memory tables
EPISODIC=$(docker exec frgops-standby psql -U frgops -d frgcrm -t -A -c "SELECT count(*) FROM episodic_memory" 2>/dev/null || echo "?")
echo "  Episodic Memory: ${EPISODIC:-?} events" | tee -a "$LOG"

# API health
for API in "brain:8160" "dashboard:8180" "embedding:8191"; do
    NAME="${API%:*}"
    PORT="${API#*:}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}/health" 2>/dev/null || echo "000")
    echo "  API $NAME: HTTP $CODE" | tee -a "$LOG"
done

# Disk
DISK=$(df -h / | tail -1 | awk '{print $5 " used, " $4 " free"}')
echo "  Disk: $DISK" | tee -a "$LOG"

# Record to episodic memory
SUMMARY="Daily brief: PM2 $ONLINE/$TOTAL, Docker $DOCKER_HEALTHY/$DOCKER_TOTAL healthy, Neo4j ${NEO4J_NODES:-?} nodes, ${EPISODIC:-?} memories"
docker exec frgops-standby psql -U frgops -d frgcrm -c \
    "INSERT INTO episodic_memory (event_type, source_agent, summary, importance, created_at)
     VALUES ('daily_brief', 'daily-brief', '$SUMMARY', 2, '$TIMESTAMP')" \
    2>/dev/null || true

echo "---" | tee -a "$LOG"
echo "[daily-brief] $TIMESTAMP Complete" | tee -a "$LOG"
