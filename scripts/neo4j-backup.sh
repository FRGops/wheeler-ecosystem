#!/bin/bash
# Wheeler Neo4j Knowledge Graph Backup — daily dump + local retention
set -euo pipefail

BACKUP_DIR="/root/backups/neo4j"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
RETENTION_DAYS=30
CONTAINER="ecosystem-graph"
NEO4J_USER="neo4j"
NEO4J_PASS="WheelerBrainOS-Graph-2026!-Neo4j-Root"

mkdir -p "$BACKUP_DIR"

echo "[neo4j-backup] $(date -u +%Y-%m-%dT%H:%M:%SZ) Starting backup..."

# Export Cypher schema + data
docker exec "$CONTAINER" cypher-shell -u "$NEO4J_USER" -p "$NEO4J_PASS" \
    "CALL apoc.export.cypher.all('$TIMESTAMP.cypher', {format: 'plain', useOptimizations: {type: 'UNWIND_BATCH', unwindBatchSize: 20}})" \
    2>/dev/null || {
    # Fallback: manual node/relationship count dump
    echo "[neo4j-backup] APOC not available — using manual dump"
    docker exec "$CONTAINER" cypher-shell -u "$NEO4J_USER" -p "$NEO4J_PASS" \
        "MATCH (n) RETURN labels(n) AS label, count(n) AS cnt ORDER BY cnt DESC" \
        > "${BACKUP_PATH}-labels.txt" 2>/dev/null
    docker exec "$CONTAINER" cypher-shell -u "$NEO4J_USER" -p "$NEO4J_PASS" \
        "MATCH ()-[r]->() RETURN type(r) AS rel_type, count(r) AS cnt ORDER BY cnt DESC" \
        > "${BACKUP_PATH}-relationships.txt" 2>/dev/null
}

# Create tarball
tar -czf "${BACKUP_PATH}.tar.gz" -C "$BACKUP_DIR" \
    "${TIMESTAMP}.cypher" "${TIMESTAMP}-labels.txt" "${TIMESTAMP}-relationships.txt" \
    2>/dev/null || tar -czf "${BACKUP_PATH}.tar.gz" \
    -C "$BACKUP_DIR" "${TIMESTAMP}-labels.txt" "${TIMESTAMP}-relationships.txt" 2>/dev/null || true

# Cleanup loose files
rm -f "${BACKUP_DIR}/${TIMESTAMP}.cypher" "${BACKUP_DIR}/${TIMESTAMP}-labels.txt" "${BACKUP_DIR}/${TIMESTAMP}-relationships.txt"

# Rotate: delete backups older than retention
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

BACKUP_COUNT=$(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)
echo "[neo4j-backup] Done — ${BACKUP_COUNT} backups retained (${RETENTION_DAYS}d retention)"
