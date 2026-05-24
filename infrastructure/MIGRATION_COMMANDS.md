# Wheeler Enterprise -- Migration Command Catalog

**Version:** 1.0.0 | **Date:** 2026-05-23 | **Owner:** SRE Team

## 3-Server Tailscale Mesh

| Server | Location | Tailscale IP | Role |
|--------|----------|-------------|------|
| EDGE | Hostinger | 100.98.163.17 | Public reverse proxy (source) |
| AIOPS | Hetzner CPX51 | 100.121.230.28 | Primary compute (target) |
| COREDB | Hetzner CX32 | 100.118.166.117 | Database server (target) |

## Tailscale Connectivity Map (used throughout)

```
EDGE (100.98.163.17)  ----190ms--->  AIOPS (100.121.230.28)  ---->  COREDB (100.118.166.117)
```

All rsync/scp/ssh commands use Tailscale IPs. TCP port 22 must be open on Tailscale interface.

---

## Pre-Migration Checklist (ALL migrations)

Run these on EVERY server before ANY migration step. Duration: ~15 min.

### 1. Backup Verification

```bash
# On EDGE (source):
sudo bash /root/infrastructure/enterprise/phase6-backup/backup-all.sh
BACKUP_EXIT=$?
ls -lh /root/infrastructure/backups/backup-*.tar.gz.gpg | tail -3
sha256sum -c /root/infrastructure/backups/backup-*.tar.gz.gpg.sha256 2>/dev/null | tail -3

# On AIOPS (target, if services already running there):
ssh root@100.121.230.28 'sudo bash /root/infrastructure/enterprise/phase6-backup/backup-all.sh'

# On COREDB (target):
ssh root@100.118.166.117 'sudo bash /root/infrastructure/enterprise/phase6-backup/backup-all.sh'

# Verify all backups passed
if [[ $BACKUP_EXIT -ne 0 ]]; then
  echo "FATAL: Backup failed on EDGE. Abort migration."
  exit 1
fi
```

### 2. Create Rollback Snapshot

```bash
# On source server, take a full pre-migration snapshot:
sudo bash /root/infrastructure/hetzner/backup/pre-migration-snapshot.sh

# Note the snapshot directory output. It will be something like:
# /root/infrastructure/backups/pre-migration-snapshots/snapshot_20260523_HHMMSS/
```

### 3. Target Environment Validation

```bash
# Target disk space (need 2x estimated service size):
ssh root@<TARGET_IP> 'df -h / /var/lib/docker /opt'

# Target Docker health:
ssh root@<TARGET_IP> 'docker info > /dev/null 2>&1 && echo "Docker OK" || echo "Docker FAIL"'

# Target memory available (need at least 2GB free):
ssh root@<TARGET_IP> "free -h | awk '/^Mem:/{print \$7}'"

# Target Tailscale up:
ssh root@<TARGET_IP> 'tailscale status > /dev/null 2>&1 && echo "Tailscale OK" || echo "Tailscale FAIL"'

# Target UFW allows Tailscale:
ssh root@<TARGET_IP> 'ufw status | grep -q "100.64.0.0/10" && echo "UFW OK" || echo "UFW WARN"'

# Target Docker compose available:
ssh root@<TARGET_IP> 'docker compose version > /dev/null 2>&1 && echo "Compose OK" || echo "Compose FAIL"'

# Target node_exporter running:
ssh root@<TARGET_IP> 'systemctl is-active node_exporter'
```

### 4. Target Dependencies Health

```bash
# When migrating to AIOPS, verify shared deps are healthy:
ssh root@100.121.230.28 '
  # PostgreSQL
  docker exec postgres-aio-main pg_isready -U postgres 2>/dev/null && echo "PG OK" || echo "PG FAIL"
  # Redis
  docker exec redis-aio-main redis-cli PING 2>/dev/null && echo "Redis OK" || echo "Redis FAIL"
  # NATS
  curl -sf http://localhost:8222/ > /dev/null 2>&1 && echo "NATS OK" || echo "NATS WARN"
'

# When migrating to COREDB, verify DB services are healthy:
ssh root@100.118.166.117 '
  docker exec postgres-coredb pg_isready -U postgres 2>/dev/null && echo "PG OK" || echo "PG FAIL"
  docker exec redis-coredb redis-cli PING 2>/dev/null && echo "Redis OK" || echo "Redis FAIL"
  curl -sf http://127.0.0.1:9000/minio/health/live > /dev/null 2>&1 && echo "MinIO OK" || echo "MinIO FAIL"
'
```

### 5. Target Port Availability

```bash
ssh root@<TARGET_IP> '
  # Check if any of these ports are already in use (adjust per service):
  for port in 8000 8098 5433 6379 8007 8088 8123 3001 3002 9090 4222 5000 3130; do
    ss -tlnp "sport = :${port}" 2>/dev/null | grep -q ":${port}" && echo "PORT IN USE: ${port}" || echo "Port ${port}: free"
  done
'
```

### 6. PM2 Config Verified (if applicable)

```bash
# On source, dump current PM2 state:
pm2 save
pm2 list > /tmp/pm2-pre-migration-$(date +%Y%m%d-%H%M%S).txt
cp /root/.pm2/dump.pm2 /root/.pm2/dump.pm2.pre-migration-$(date +%Y%m%d-%H%M%S)

# On target, verify PM2 is installed and running:
ssh root@<TARGET_IP> 'pm2 ping && echo "PM2 OK" || echo "PM2 FAIL"'
```

### 7. Docker Config Verified (if applicable)

```bash
# On source, verify compose files parse:
docker compose -f /path/to/docker-compose.yml config > /dev/null 2>&1 && echo "Compose valid" || echo "Compose INVALID"

# On target, verify Docker networks exist:
ssh root@<TARGET_IP> 'docker network ls --format "{{.Name}}"'
```

### 8. Logs Path Verified

```bash
# On target, ensure log directory exists:
ssh root@<TARGET_IP> 'mkdir -p /var/log/wheeler /opt/wheeler/logs'
ssh root@<TARGET_IP> 'test -w /var/log/wheeler && echo "Logs dir writable" || echo "Logs dir NOT writable"'
```

---

## Scenario A: Move Docker Service EDGE -> AIOPS

Applies to: prediction-radar-worker, prediction-radar-scheduler, private-ai-webui, temporal-server, usesend-app

### A.1 Pre-flight (on EDGE)

```bash
# Identify all containers for the service:
SERVICE="<service-name>"
CONTAINERS=$(docker ps --filter "name=${SERVICE}" --format '{{.Names}}')
echo "Containers to migrate: ${CONTAINERS}"

# Record container images and tags:
for c in $CONTAINERS; do
  docker inspect "$c" --format '{{.Name}} {{.Config.Image}}' >> /tmp/${SERVICE}-pre-migration-images.txt
done

# Record container environment:
for c in $CONTAINERS; do
  docker inspect "$c" --format '{{.Name}}: {{range .Config.Env}}{{.}} {{end}}' >> /tmp/${SERVICE}-pre-migration-env.txt
done

# Identify compose file location:
COMPOSE_FILE=$(docker inspect "$(echo "$CONTAINERS" | head -1)" --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null || echo "")
if [[ -z "$COMPOSE_FILE" ]]; then
  # Search for compose file containing this service
  COMPOSE_FILE=$(grep -rl "${SERVICE}" /root/infrastructure/ --include='*.yml' --include='*.yaml' | head -1)
fi
echo "Compose file: ${COMPOSE_FILE}"

# Identify volumes used:
for c in $CONTAINERS; do
  docker inspect "$c" --format '{{range .Mounts}}{{.Type}}|{{.Source}}|{{.Destination}} {{end}}' >> /tmp/${SERVICE}-pre-migration-volumes.txt
done

# Record port mappings:
for c in $CONTAINERS; do
  docker inspect "$c" --format '{{.Name}}: {{range $p,$c := .NetworkSettings.Ports}}{{$p}}->{{(index $c 0).HostPort}} {{end}}' >> /tmp/${SERVICE}-pre-migration-ports.txt
done
```

### A.2 Backup (on EDGE)

```bash
# Full service backup (docker commit + volume backup):
BACKUP_DIR="/root/infrastructure/backups/migration-${SERVICE}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"

# Save compose file:
cp "${COMPOSE_FILE}" "${BACKUP_DIR}/docker-compose.yml"

# Save .env files:
find "$(dirname "${COMPOSE_FILE}")" -maxdepth 1 -name '.env*' -exec cp {} "${BACKUP_DIR}/" \;

# Backup volumes:
docker run --rm \
  $(for c in $CONTAINERS; do docker inspect "$c" --format '{{range .Mounts}}{{if eq .Type "volume"}}-v {{.Name}}:/backup-src/{{.Name}}:ro {{end}}{{end}}'; done) \
  -v "${BACKUP_DIR}/volumes:/backup-dst" \
  alpine:latest \
  sh -c 'for d in /backup-src/*; do tar czf "/backup-dst/$(basename $d).tar.gz" -C "$d" . 2>/dev/null; done'

# Commit current container state as image (rollback safety net):
for c in $CONTAINERS; do
  docker commit "$c" "migration-rollback/${c}:$(date +%Y%m%d-%H%M%S)"
done
```

### A.3 Migrate (rsync with exclusions)

```bash
# On EDGE, create a clean copy of the service directory:
SERVICE_SRC_DIR="$(dirname "${COMPOSE_FILE}")"
MIGRATION_STAGING="/tmp/migration-${SERVICE}-${TIMESTAMP}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "${MIGRATION_STAGING}"

# rsync with EXACT exclusions (no node_modules, .venv, dist, build, cache, logs, .git, __pycache__, *.pyc, .env):
rsync -avz --delete \
  --exclude='node_modules' \
  --exclude='.venv' \
  --exclude='venv' \
  --exclude='dist' \
  --exclude='build' \
  --exclude='.next' \
  --exclude='cache' \
  --exclude='.cache' \
  --exclude='logs' \
  --exclude='*.log' \
  --exclude='.git' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='*.pyo' \
  --exclude='.env' \
  --exclude='.env.local' \
  --exclude='.env.production' \
  --exclude='tmp' \
  --exclude='.tmp' \
  --exclude='coverage' \
  --exclude='.nyc_output' \
  "${SERVICE_SRC_DIR}/" \
  "${MIGRATION_STAGING}/"

echo "Staging size: $(du -sh ${MIGRATION_STAGING} | cut -f1)"

# Transfer to AIOPS over Tailscale (preserving permissions, using compression):
rsync -avz --delete \
  -e "ssh -o StrictHostKeyChecking=accept-new" \
  "${MIGRATION_STAGING}/" \
  "root@100.121.230.28:/opt/wheeler/migrations/${SERVICE}/"

echo "Transfer complete. Verify on target:"
ssh root@100.121.230.28 "ls -la /opt/wheeler/migrations/${SERVICE}/"
```

### A.4 Deploy on Target (on AIOPS)

```bash
ssh root@100.121.230.28 << 'DEPLOY_EOF'
SERVICE="<service-name>"
MIGRATION_DIR="/opt/wheeler/migrations/${SERVICE}"
COMPOSE_FILE="${MIGRATION_DIR}/docker-compose.yml"

cd "${MIGRATION_DIR}"

# Verify compose file is valid:
docker compose -f "${COMPOSE_FILE}" config > /dev/null 2>&1 || {
  echo "FATAL: Compose file validation failed"
  exit 1
}

# Check for .env file; copy if missing:
if [[ ! -f "${MIGRATION_DIR}/.env" ]]; then
  echo "WARNING: No .env file in migration. Checking /opt/wheeler/config/envs/"
  if [[ -f "/opt/wheeler/config/envs/${SERVICE}.env" ]]; then
    cp "/opt/wheeler/config/envs/${SERVICE}.env" "${MIGRATION_DIR}/.env"
    echo "Copied env from /opt/wheeler/config/envs/${SERVICE}.env"
  else
    echo "FATAL: No .env file found. Create one before proceeding."
    exit 1
  fi
fi

# Pull images:
docker compose -f "${COMPOSE_FILE}" pull

# Start the service:
docker compose -f "${COMPOSE_FILE}" up -d

# Wait for containers:
sleep 5
docker compose -f "${COMPOSE_FILE}" ps
DEPLOY_EOF
```

### A.5 Health Check (on AIOPS)

```bash
ssh root@100.121.230.28 << 'HEALTH_EOF'
SERVICE="<service-name>"

# Wait up to 60 seconds for healthy status:
ATTEMPT=0
MAX_ATTEMPTS=30
while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
  UNHEALTHY=$(docker ps --filter "name=${SERVICE}" --filter "health=unhealthy" --format '{{.Names}}' 2>/dev/null)
  if [[ -n "$UNHEALTHY" ]]; then
    echo "UNHEALTHY containers: $UNHEALTHY"
    docker logs --tail 20 $UNHEALTHY
    exit 1
  fi
  
  ALL_RUNNING=$(docker ps --filter "name=${SERVICE}" --format '{{.Names}}' 2>/dev/null | wc -l)
  if [[ $ALL_RUNNING -gt 0 ]]; then
    echo "Containers running: ${ALL_RUNNING}"
  fi
  
  # Try health endpoint (adjust port per service):
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:<SERVICE_PORT>/health 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "HEALTH CHECK PASSED (HTTP 200)"
    exit 0
  fi
  
  sleep 2
  ATTEMPT=$((ATTEMPT + 1))
done

echo "HEALTH CHECK FAILED after 60 seconds"
exit 1
HEALTH_EOF
```

### A.6 Cut Over

```bash
# Step 1: Stop old service on EDGE (graceful):
ssh root@100.98.163.17 "
  SERVICE='<service-name>'
  cd \$(dirname \$(grep -rl \"\${SERVICE}\" /root/infrastructure/hostinger/ --include='*.yml' | head -1))
  docker compose stop \"\${SERVICE}\" 2>/dev/null
  sleep 3
  docker ps --filter 'name=\${SERVICE}' --format '{{.Names}}: {{.Status}}'
"

# Step 2: Update Traefik routing on EDGE to point to AIOPS Tailscale IP:
ssh root@100.98.163.17 "
  # Edit the Traefik dynamic config or router to point to AIOPS
  # Example: sed replace upstream target
  # Actual file depends on service -- typically:
  # /root/infrastructure/hostinger/traefik/dynamic.yml or routers.yml
  
  # For services proxied through Traefik, update the upstream:
  sed -i 's|url: \"http://[^:]*:<PORT>\"|url: \"http://100.121.230.28:<PORT>\"|g' \
    /root/infrastructure/hostinger/traefik/dynamic.yml
  
  # Reload Traefik (zero-downtime):
  docker restart traefik 2>/dev/null
  sleep 3
  curl -sf http://localhost:8080/api/rawdata > /dev/null && echo 'Traefik reloaded OK' || echo 'Traefik reload FAIL'
"

# Step 3: Verify service accessible via new routing:
curl -sf https://<service-domain>.wheeler.ai/health && echo "PUBLIC CUTOVER OK" || echo "PUBLIC CUTOVER FAIL"

# Step 4: Remove old containers on EDGE (keep for 24h then remove):
ssh root@100.98.163.17 "
  SERVICE='<service-name>'
  docker ps -a --filter 'name=\${SERVICE}' --format '{{.Names}}' | xargs -r docker rm 2>/dev/null
  echo 'Old containers removed from EDGE'
"
```

### A.7 Rollback

```bash
# If migration health check fails or service is degraded, rollback IMMEDIATELY:
ROLLBACK_SERVICE="<service-name>"
ROLLBACK_TIMESTAMP="<from-step-A.2>"

# Step 1: Stop failed service on AIOPS:
ssh root@100.121.230.28 "
  cd /opt/wheeler/migrations/${ROLLBACK_SERVICE}
  docker compose down --timeout 10
  docker ps --filter 'name=${ROLLBACK_SERVICE}'
"

# Step 2: Restore EDGE Traefik routing back to local:
ssh root@100.98.163.17 "
  # Restore Traefik dynamic config from backup:
  cp /root/infrastructure/hostinger/traefik/dynamic.yml.bak-${ROLLBACK_TIMESTAMP} \
     /root/infrastructure/hostinger/traefik/dynamic.yml 2>/dev/null || {
    # Fallback: point back to localhost
    sed -i 's|url: \"http://100.121.230.28:<PORT>\"|url: \"http://127.0.0.1:<PORT>\"|g' \
      /root/infrastructure/hostinger/traefik/dynamic.yml
  }
  docker restart traefik
  sleep 3
  curl -sf http://localhost:8080/api/rawdata > /dev/null && echo 'Traefik routing restored' || echo 'FAIL'
"

# Step 3: Restart old service on EDGE from Docker commit:
ssh root@100.98.163.17 "
  SERVICE='${ROLLBACK_SERVICE}'
  cd \$(dirname \$(grep -rl \"\${SERVICE}\" /root/infrastructure/hostinger/ --include='*.yml' | head -1))
  docker compose up -d \"\${SERVICE}\"
  sleep 5
  docker ps --filter 'name=\${SERVICE}' --filter 'health=healthy'
"

# Step 4: Verify public health:
curl -sf https://<service-domain>.wheeler.ai/health && echo "ROLLBACK OK" || echo "ROLLBACK FAILED - MANUAL INTERVENTION REQUIRED"

# Step 5: Clean up migration staging on AIOPS:
ssh root@100.121.230.28 "rm -rf /opt/wheeler/migrations/${ROLLBACK_SERVICE}"
```

---

## Scenario B: Move Database EDGE -> COREDB

Applies to: shared-postgres-recovery postgres instance on EDGE

### B.1 Pre-flight (on EDGE)

```bash
# Identify postgres container on EDGE:
PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
echo "Postgres container: ${PG_CONTAINER}"

# Get connection info:
PG_USER=$(docker exec "${PG_CONTAINER}" printenv POSTGRES_USER 2>/dev/null || echo "postgres")
PG_PASSWORD=$(docker exec "${PG_CONTAINER}" printenv POSTGRES_PASSWORD 2>/dev/null || echo "")
PG_PORT=$(docker inspect "${PG_CONTAINER}" --format '{{range $p,$c := .NetworkSettings.Ports}}{{if eq $p "5432/tcp"}}{{(index $c 0).HostPort}}{{end}}{{end}}' 2>/dev/null || echo "5432")
echo "PG User: ${PG_USER}, Port: ${PG_PORT}"

# List all databases:
docker exec "${PG_CONTAINER}" psql -U "${PG_USER}" -tAc "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null

# Get total database size:
docker exec "${PG_CONTAINER}" psql -U "${PG_USER}" -tAc "SELECT pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datistemplate = false;" 2>/dev/null

# Record current pg_hba.conf and postgresql.conf:
docker exec "${PG_CONTAINER}" cat /var/lib/postgresql/data/pg_hba.conf > /tmp/ed-pg-hba.conf
docker exec "${PG_CONTAINER}" cat /var/lib/postgresql/data/postgresql.conf > /tmp/ed-pg-postgresql.conf

# Identify volume:
PG_VOLUME=$(docker inspect "${PG_CONTAINER}" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}' 2>/dev/null)
echo "PG Volume: ${PG_VOLUME}"
```

### B.2 Backup (on EDGE)

```bash
BACKUP_DIR="/root/infrastructure/backups/migration-postgres-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"

# Full pg_dumpall (roles + all databases):
docker exec "${PG_CONTAINER}" pg_dumpall -U "${PG_USER}" --clean --if-exists | gzip > "${BACKUP_DIR}/full-pg_dumpall.sql.gz"

# Verify dump integrity:
gunzip -t "${BACKUP_DIR}/full-pg_dumpall.sql.gz" && echo "Dump valid" || echo "DUMP INVALID - ABORT"

# Per-database dumps (for selective restore if needed):
for db in $(docker exec "${PG_CONTAINER}" psql -U "${PG_USER}" -tAc "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null); do
  docker exec "${PG_CONTAINER}" pg_dump -U "${PG_USER}" -d "$db" --clean --if-exists --no-owner | gzip > "${BACKUP_DIR}/${db}.sql.gz"
  gunzip -t "${BACKUP_DIR}/${db}.sql.gz" && echo "  $db: OK" || echo "  $db: FAIL"
done

# Backup volume (if small enough):
docker run --rm -v "${PG_VOLUME}:/pgdata:ro" -v "${BACKUP_DIR}:/backup" alpine:latest \
  tar czf "/backup/${PG_VOLUME}.tar.gz" -C /pgdata . 2>/dev/null && \
  echo "Volume backup OK ($(du -h ${BACKUP_DIR}/${PG_VOLUME}.tar.gz | cut -f1))" || \
  echo "Volume backup FAILED - pg_dumpall is sufficient"

# Copy backup to COREDB over Tailscale:
rsync -avz -e "ssh -o StrictHostKeyChecking=accept-new" "${BACKUP_DIR}/" "root@100.118.166.117:/root/infrastructure/backups/migration-postgres/"
echo "Backup synced to COREDB"
```

### B.3 Migrate (restore on COREDB)

```bash
ssh root@100.118.166.117 << 'RESTORE_EOF'
BACKUP_DIR="/root/infrastructure/backups/migration-postgres"
PG_USER="postgres"

# Find the latest dump:
DUMP_FILE=$(ls -t ${BACKUP_DIR}/full-pg_dumpall.sql.gz 2>/dev/null | head -1)
if [[ -z "$DUMP_FILE" ]]; then
  echo "FATAL: No dump file found on COREDB"
  exit 1
fi
echo "Restoring from: ${DUMP_FILE}"

# Identify COREDB postgres container:
PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
if [[ -z "$PG_CONTAINER" ]]; then
  echo "FATAL: No postgres container running on COREDB"
  exit 1
fi
echo "Target container: ${PG_CONTAINER}"

# Decompress and restore:
gunzip -c "${DUMP_FILE}" | docker exec -i "${PG_CONTAINER}" psql -U "${PG_USER}" 2>&1 | tee /tmp/pg-restore.log

# Check for errors:
if grep -iE 'ERROR|FATAL' /tmp/pg-restore.log > /dev/null 2>&1; then
  echo "WARNING: Errors found during restore. Review /tmp/pg-restore.log"
  grep -iE 'ERROR|FATAL' /tmp/pg-restore.log | head -20
else
  echo "Restore completed without errors"
fi

# Verify databases exist:
echo "Databases on COREDB:"
docker exec "${PG_CONTAINER}" psql -U "${PG_USER}" -tAc "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datistemplate = false;"

# Verify row counts (spot-check key tables):
for db in $(docker exec "${PG_CONTAINER}" psql -U "${PG_USER}" -tAc "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null); do
  TABLE_COUNT=$(docker exec "${PG_CONTAINER}" psql -U "${PG_USER}" -d "$db" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null || echo "0")
  echo "  ${db}: ${TABLE_COUNT} tables"
done
RESTORE_EOF
```

### B.4 Deploy / Bind to Tailscale IP (on COREDB)

```bash
ssh root@100.118.166.117 << 'DEPLOY_EOF'
# Ensure postgres is listening on Tailscale IP:
PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)

# Check current bind:
docker inspect "${PG_CONTAINER}" --format '{{range $p,$c := .NetworkSettings.Ports}}{{$p}} -> {{(index $c 0).HostIp}}:{{(index $c 0).HostPort}}{{"\n"}}{{end}}'

# If bound to 0.0.0.0, fix to Tailscale IP. This requires updating compose file:
# ports:
#   - "100.118.166.117:5432:5432"   # NOT "5432:5432"
echo "Verify port binding: ss -tlnp | grep 5432"
ss -tlnp | grep 5432

# Update pg_hba.conf to allow connections from AIOPS Tailscale IP:
docker exec "${PG_CONTAINER}" bash -c "echo 'host all all 100.121.230.28/32 md5' >> /var/lib/postgresql/data/pg_hba.conf"
docker exec "${PG_CONTAINER}" psql -U postgres -c "SELECT pg_reload_conf();"

# Verify connectivity from AIOPS:
echo "Test from AIOPS (run manually):"
echo "  ssh root@100.121.230.28 'pg_isready -h 100.118.166.117 -p 5432 -U postgres'"
DEPLOY_EOF
```

### B.5 Health Check (on COREDB)

```bash
ssh root@100.118.166.117 << 'HEALTH_EOF'
PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)

# Basic check:
docker exec "${PG_CONTAINER}" pg_isready -U postgres && echo "PG is ready" || echo "PG NOT READY"

# Check replication state (if applicable):
docker exec "${PG_CONTAINER}" psql -U postgres -tAc "SELECT pg_is_in_recovery();" 2>/dev/null

# Check active connections:
docker exec "${PG_CONTAINER}" psql -U postgres -tAc "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null

# Verify from AIOPS:
echo "Run on AIOPS: pg_isready -h 100.118.166.117 -p 5432 -U postgres"
HEALTH_EOF
```

### B.6 Cut Over

```bash
# Step 1: Update application connection strings on AIOPS to point to COREDB:
ssh root@100.121.230.28 "
  # Update DATABASE_URL in .env files for services that used the EDGE postgres:
  # Replace EDGE IPs with COREDB tailscale IP:
  find /opt/wheeler/config/envs/ -name '*.env' -exec sed -i 's|@100.98.163.17:|@100.118.166.117:|g' {} \;
  
  # Restart dependent services:
  for svc in prediction-radar-api ravynai-api; do
    cd /opt/wheeler/deploy/\${svc}/current 2>/dev/null && docker compose restart || true
  done
  echo 'Connection strings updated'
"

# Step 2: Stop old postgres on EDGE (after verifying all apps work):
ssh root@100.98.163.17 "
  PG_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
  docker stop \"\${PG_CONTAINER}\"
  echo 'EDGE postgres stopped'
  
  # DO NOT remove the container or volume for 7 days.
  # Tag it for deferred cleanup:
  docker rename \"\${PG_CONTAINER}\" \"\${PG_CONTAINER}-decommissioned-$(date +%Y%m%d)\"
"

# Step 3: Verify no apps are connecting to old postgres:
sleep 30
ssh root@100.98.163.17 "
  PG_CONTAINER=\$(docker ps -a --format '{{.Names}}' | grep 'postgres.*decommissioned' | head -1)
  docker logs --tail 10 \"\${PG_CONTAINER}\" 2>/dev/null | grep -i connection
  echo 'If connections still coming in, revert connection strings immediately'
"
```

### B.7 Rollback

```bash
ROLLBACK_BACKUP_DIR="/root/infrastructure/backups/migration-postgres"
ROLLBACK_TIMESTAMP="<from-step-B.2>"

# Step 1: Stop applications that switched to COREDB:
ssh root@100.121.230.28 "
  for svc in prediction-radar-api ravynai-api; do
    cd /opt/wheeler/deploy/\${svc}/current 2>/dev/null && docker compose stop || true
  done
"

# Step 2: Start old postgres on EDGE:
ssh root@100.98.163.17 "
  OLD_PG=\$(docker ps -a --format '{{.Names}}' | grep 'postgres.*decommissioned' | head -1)
  docker start \"\${OLD_PG}\"
  sleep 3
  docker exec \"\${OLD_PG}\" pg_isready -U postgres && echo 'EDGE PG restored' || echo 'FAIL'
"

# Step 3: Revert application connection strings on AIOPS:
ssh root@100.121.230.28 "
  find /opt/wheeler/config/envs/ -name '*.env' -exec sed -i 's|@100.118.166.117:|@100.98.163.17:|g' {} \;
  
  for svc in prediction-radar-api ravynai-api; do
    cd /opt/wheeler/deploy/\${svc}/current 2>/dev/null && docker compose up -d || true
  done
  echo 'Connection strings reverted'
"

# Step 4: Verify:
curl -sf https://predictionradar.wheeler.ai/health && echo "ROLLBACK OK" || echo "ROLLBACK FAILED"

# Step 5: (Optional) Remove restored data from COREDB:
ssh root@100.118.166.117 "
  PG_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
  for db in <list-of-restored-dbs>; do
    docker exec \"\${PG_CONTAINER}\" psql -U postgres -c \"DROP DATABASE IF EXISTS \\\"\\\${db}\\\";\"
  done
"
```

---

## Scenario C: Move PM2 Service EDGE -> AIOPS

Applies to: Any PM2-managed Node.js/Python service currently on EDGE

### C.1 Pre-flight (on EDGE)

```bash
APP_NAME="<pm2-app-name>"

# Get app details:
pm2 show "${APP_NAME}" 2>/dev/null || { echo "App not found"; exit 1; }

# Record current state:
pm2 show "${APP_NAME}" > "/tmp/pm2-${APP_NAME}-pre-migration.txt"
APP_DIR=$(pm2 show "${APP_NAME}" | grep 'exec cwd' | awk '{print $NF}' 2>/dev/null || echo "")
echo "App directory: ${APP_DIR}"

# Record current git commit:
cd "${APP_DIR}" 2>/dev/null && git rev-parse HEAD > "/tmp/pm2-${APP_NAME}-commit.txt" && echo "Git commit recorded"

# Record env vars:
pm2 env $(pm2 show "${APP_NAME}" | grep 'pm2 id' | awk '{print $NF}') > "/tmp/pm2-${APP_NAME}-env.txt" 2>/dev/null

# Record resource usage baseline:
pm2 monit --no-daemon 2>/dev/null &
MONIT_PID=$!
sleep 5
kill $MONIT_PID 2>/dev/null || true
pm2 show "${APP_NAME}" | grep -E 'memory|cpu|restarts'

# Identify data dependencies:
echo "Check what this app connects to:"
grep -rn 'DATABASE_URL\|REDIS_URL\|NATS_URL\|RABBITMQ_URL' "${APP_DIR}"/.env* "${APP_DIR}"/ecosystem.config.* 2>/dev/null | head -20
```

### C.2 Backup (on EDGE)

```bash
BACKUP_DIR="/root/infrastructure/backups/migration-pm2-${APP_NAME}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"

# Save PM2 state:
pm2 save
cp /root/.pm2/dump.pm2 "${BACKUP_DIR}/dump.pm2"

# Save ecosystem config:
find "${APP_DIR}" -maxdepth 2 -name "ecosystem.config.*" -exec cp {} "${BACKUP_DIR}/" \;

# Save .env files:
find "${APP_DIR}" -maxdepth 2 -name '.env*' ! -path '*/node_modules/*' -exec cp {} "${BACKUP_DIR}/" \;

# Full app directory backup (excluding node_modules and logs):
tar czf "${BACKUP_DIR}/${APP_NAME}-source.tar.gz" \
  --exclude='node_modules' \
  --exclude='.venv' \
  --exclude='venv' \
  --exclude='dist' \
  --exclude='build' \
  --exclude='.next' \
  --exclude='logs' \
  --exclude='*.log' \
  --exclude='.git' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='cache' \
  --exclude='.cache' \
  -C "$(dirname "${APP_DIR}")" \
  "$(basename "${APP_DIR}")"

echo "Backup size: $(du -h ${BACKUP_DIR}/${APP_NAME}-source.tar.gz | cut -f1)"
```

### C.3 Migrate

```bash
# Transfer to AIOPS:
rsync -avz \
  -e "ssh -o StrictHostKeyChecking=accept-new" \
  "${BACKUP_DIR}/${APP_NAME}-source.tar.gz" \
  "root@100.121.230.28:/tmp/"

# Also transfer ecosystem config and env:
scp "${BACKUP_DIR}/"ecosystem* "root@100.121.230.28:/tmp/"
scp "${BACKUP_DIR}/.env"* "root@100.121.230.28:/tmp/" 2>/dev/null || true

echo "Files transferred to AIOPS"
```

### C.4 Deploy on Target (on AIOPS)

```bash
ssh root@100.121.230.28 << 'DEPLOY_PM2'
APP_NAME="<pm2-app-name>"
APP_BASE="/opt/pm2-apps"
APP_DIR="${APP_BASE}/${APP_NAME}"

mkdir -p "${APP_BASE}"

# Extract source:
tar xzf "/tmp/${APP_NAME}-source.tar.gz" -C "${APP_BASE}/"

# Install dependencies:
cd "${APP_DIR}"
if [[ -f "package.json" ]]; then
  npm install --production 2>&1 | tail -5
elif [[ -f "requirements.txt" ]]; then
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt 2>&1 | tail -5
fi

# Copy env files:
cp /tmp/.env* "${APP_DIR}/" 2>/dev/null || true
cp /tmp/ecosystem* "${APP_DIR}/" 2>/dev/null || true

# Update env files - replace EDGE IPs with AIOPS/COREDB IPs as needed:
find "${APP_DIR}" -maxdepth 1 -name '.env*' -exec sed -i 's|100.98.163.17|100.121.230.28|g' {} \;

# Start with PM2:
if [[ -f "${APP_DIR}/ecosystem.config.js" ]]; then
  cd "${APP_DIR}" && pm2 start ecosystem.config.js
elif [[ -f "${APP_DIR}/ecosystem.config.cjs" ]]; then
  cd "${APP_DIR}" && pm2 start ecosystem.config.cjs
else
  # Manual start - adapt as needed:
  SCRIPT=$(pm2 show "${APP_NAME}" 2>/dev/null | grep 'script path' | awk '{print $NF}' || echo "")
  pm2 start "${SCRIPT:-${APP_DIR}/index.js}" --name "${APP_NAME}" -i 1
fi

pm2 save
pm2 status
DEPLOY_PM2
```

### C.5 Health Check (on AIOPS)

```bash
ssh root@100.121.230.28 << 'HEALTH_PM2'
APP_NAME="<pm2-app-name>"

# PM2 status:
STATUS=$(pm2 show "${APP_NAME}" 2>/dev/null | grep 'status' | awk '{print $NF}')
echo "PM2 status: ${STATUS}"
if [[ "$STATUS" != "online" ]]; then
  echo "PM2 app not online. Checking logs:"
  pm2 logs "${APP_NAME}" --lines 30 --nostream
  exit 1
fi

# Check restart count (should not be climbing):
RESTARTS=$(pm2 show "${APP_NAME}" | grep 'restarts' | awk '{print $NF}')
echo "Restart count: ${RESTARTS}"
if [[ "$RESTARTS" -gt 5 ]]; then
  echo "WARNING: High restart count"
fi

# Wait for stability (no restarts for 30 seconds):
INITIAL_RESTARTS=$(pm2 show "${APP_NAME}" | grep 'restarts' | awk '{print $NF}')
sleep 30
FINAL_RESTARTS=$(pm2 show "${APP_NAME}" | grep 'restarts' | awk '{print $NF}')
if [[ "$INITIAL_RESTARTS" -ne "$FINAL_RESTARTS" ]]; then
  echo "App is restarting. Check:"
  pm2 logs "${APP_NAME}" --lines 30 --nostream
  exit 1
fi

# Try health endpoint if applicable:
if pm2 show "${APP_NAME}" | grep -q 'health'; then
  HEALTH_URL=$(grep -oP 'http://localhost:\d+/health' "${APP_DIR}/.env"* "${APP_DIR}/ecosystem.config."* 2>/dev/null | head -1 || echo "")
  if [[ -n "$HEALTH_URL" ]]; then
    curl -sf "$HEALTH_URL" && echo "HEALTH OK" || echo "HEALTH FAIL"
  fi
fi

echo "PM2 ${APP_NAME}: ONLINE and STABLE"
HEALTH_PM2
```

### C.6 Cut Over

```bash
# Step 1: Stop PM2 app on EDGE:
ssh root@100.98.163.17 "
  pm2 stop <pm2-app-name>
  pm2 delete <pm2-app-name>
  pm2 save
  echo 'EDGE PM2 app stopped and removed from startup'
"

# Step 2: Update any Traefik routing from EDGE to AIOPS (if app exposes HTTP):
ssh root@100.98.163.17 "
  sed -i 's|url: \"http://127.0.0.1:<PORT>\"|url: \"http://100.121.230.28:<PORT>\"|g' \
    /root/infrastructure/hostinger/traefik/dynamic.yml
  docker restart traefik
  sleep 3
  curl -sf http://localhost:8080/api/rawdata > /dev/null && echo 'Traefik updated' || echo 'FAIL'
"

# Step 3: Verify AIOPS app still stable:
ssh root@100.121.230.28 "pm2 show <pm2-app-name> | grep status"

# Step 4: Clean up EDGE source (keep backup, remove running code):
ssh root@100.98.163.17 "
  mv <app-dir> <app-dir>.decommissioned-$(date +%Y%m%d)
  echo 'Source archived on EDGE'
"
```

### C.7 Rollback

```bash
# Step 1: Stop PM2 app on AIOPS:
ssh root@100.121.230.28 "
  pm2 stop <pm2-app-name>
  pm2 delete <pm2-app-name>
  pm2 save
"

# Step 2: Restore PM2 app on EDGE from backup:
ssh root@100.98.163.17 "
  APP_DIR='<app-dir>'
  # If archived with .decommissioned suffix:
  if [[ -d \"\${APP_DIR}.decommissioned-\"* ]]; then
    mv \${APP_DIR}.decommissioned-* \"\${APP_DIR}\"
  fi
  cd \"\${APP_DIR}\"
  pm2 start ecosystem.config.js 2>/dev/null || pm2 start index.js --name <pm2-app-name>
  pm2 save
  echo 'App restored on EDGE'
"

# Step 3: Revert Traefik routing if changed:
ssh root@100.98.163.17 "
  sed -i 's|url: \"http://100.121.230.28:<PORT>\"|url: \"http://127.0.0.1:<PORT>\"|g' \
    /root/infrastructure/hostinger/traefik/dynamic.yml
  docker restart traefik
"

# Step 4: Verify:
ssh root@100.98.163.17 "pm2 show <pm2-app-name> | grep status"
```

---

## Scenario D: Remove Duplicate Monitoring on COREDB

COREDB has Prometheus/Grafana/Loki. Per server-role-policies.md, COREDB should only have exporters (node_exporter, postgres_exporter, redis_exporter). The monitoring stack runs on AIOPS.

### D.1 Pre-flight (on COREDB)

```bash
ssh root@100.118.166.117 << 'PREFLIGHT'
# Identify monitoring containers:
echo "=== Monitoring containers on COREDB ==="
docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep -iE 'grafana|prometheus|loki|alertmanager|netdata|uptime'

# Check if these are receiving/generating data:
for c in $(docker ps --format '{{.Names}}' | grep -iE 'grafana|prometheus|loki|alertmanager'); do
  echo "--- ${c} ---"
  docker inspect "$c" --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
done

# Check what port bindings exist:
ss -tlnp | grep -E '3002|9090|3100|9093|3001|19999'

# Check if any scraped metrics are actually needed LOCALLY:
echo "Prometheus targets:"
curl -sf http://127.0.0.1:9090/api/v1/targets 2>/dev/null | python3 -m json.tool 2>/dev/null | grep -E 'job|scrapeUrl' | head -20 || echo "Prometheus not reachable"
PREFLIGHT
```

### D.2 Backup (on COREDB)

```bash
ssh root@100.118.166.117 << 'BACKUP_MON'
BACKUP_DIR="/root/infrastructure/backups/migration-monitoring-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"

# Backup Grafana dashboards and configs:
for c in $(docker ps --format '{{.Names}}' | grep -i grafana); do
  docker cp "${c}:/var/lib/grafana" "${BACKUP_DIR}/grafana-data" 2>/dev/null && echo "Grafana data backed up" || echo "WARN: Grafana cp failed"
done

# Backup Prometheus TSDB snapshots (WARNING: may be large):
for c in $(docker ps --format '{{.Names}}' | grep -i prometheus); do
  docker exec "${c}" sh -c 'curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot' 2>/dev/null && \
    echo "Prometheus snapshot created" || echo "WARN: TSDB snapshot skipped"
done

# Backup any compose files that define monitoring:
find /root/infrastructure -name '*.yml' -exec grep -l 'grafana\|prometheus\|loki' {} \; | while read f; do
  cp "$f" "${BACKUP_DIR}/$(basename $(dirname $f))-$(basename $f)"
done

echo "Monitoring backup saved to ${BACKUP_DIR}"
BACKUP_MON
```

### D.3 Migrate (disable on COREDB, verify on AIOPS)

```bash
# Step 1: Verify AIOPS monitoring is healthy and scraping COREDB exporters:
ssh root@100.121.230.28 << 'VERIFY_AIOPS'
# Check Prometheus targets include COREDB:
curl -sf http://127.0.0.1:9090/api/v1/targets 2>/dev/null | python3 -m json.tool 2>/dev/null | grep -E '100.118.166.117' || echo "WARN: No COREDB targets in AIOPS Prometheus"

# Ensure AIOPS Grafana is running:
docker ps --filter 'name=grafana' --format '{{.Names}} {{.Status}}'

# Ensure AIOPS Loki is receiving logs:
curl -sf http://127.0.0.1:3100/ready 2>/dev/null && echo "Loki ready" || echo "WARN: Loki not ready"

# Ensure COREDB exporters are reachable from AIOPS:
curl -sf http://100.118.166.117:9100/metrics 2>/dev/null | head -1 && echo "node_exporter reachable" || echo "WARN: node_exporter not reachable"
curl -sf http://100.118.166.117:9187/metrics 2>/dev/null | head -1 && echo "pg_exporter reachable" || echo "WARN: pg_exporter not reachable"
VERIFY_AIOPS
```

### D.4 Stop monitoring on COREDB

```bash
ssh root@100.118.166.117 << 'STOP_MON'
# Gracefully stop monitoring containers:
for c in $(docker ps --format '{{.Names}}' | grep -iE 'grafana|prometheus|loki|alertmanager'); do
  echo "Stopping: ${c}"
  docker stop "$c" 2>/dev/null
done

sleep 3

# Verify stopped:
docker ps --format '{{.Names}}' | grep -iE 'grafana|prometheus|loki|alertmanager' && echo "SOME STILL RUNNING" || echo "All monitoring stopped"

# Verify exporters are still running (they should be):
docker ps --format '{{.Names}} {{.Status}}' | grep -iE 'exporter|node_export'
STOP_MON
```

### D.5 Health Check - Verify monitoring still works from AIOPS

```bash
# From AIOPS, verify we can still see COREDB metrics:
ssh root@100.121.230.28 << 'MON_HEALTH'
# Check Prometheus is still scraping:
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=up{instance=~".*100.118.166.117.*"}' 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('data', {}).get('result', [])
for r in results:
    print(f\"{r['metric']['job']}: {r['value'][1]}\")
" 2>/dev/null || echo "Cannot parse Prometheus response"

# Check Grafana dashboards still load:
curl -sf http://127.0.0.1:3002/api/health 2>/dev/null && echo "Grafana healthy" || echo "Grafana FAIL"

# Verify Loki still receiving COREDB logs:
curl -sf 'http://127.0.0.1:3100/loki/api/v1/label' 2>/dev/null | python3 -m json.tool 2>/dev/null | head -5 || echo "Loki check failed"
MON_HEALTH
```

### D.6 Cleanup (on COREDB, after 7 days of stable operation)

```bash
ssh root@100.118.166.117 << 'CLEANUP'
# Remove stopped monitoring containers:
for c in $(docker ps -a --format '{{.Names}}' | grep -iE 'grafana|prometheus|loki|alertmanager'); do
  echo "Removing: ${c}"
  docker rm "$c"
done

# Remove monitoring images (optional, frees space):
for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -iE 'grafana|prometheus|loki|alertmanager'); do
  echo "Removing image: ${img}"
  docker rmi "$img" 2>/dev/null || echo "  (in use by other container, skipped)"
done

# Remove monitoring volumes (CAUTION: data is gone):
echo "Monitoring volumes to manually review:"
docker volume ls --format '{{.Name}}' | grep -iE 'grafana|prometheus|loki'
echo ""
echo "To remove (after confirming AIOPS works): docker volume rm <name>"
echo "DO NOT remove exporter-related volumes (node_exporter, pg_exporter, redis_exporter)"

# Remove monitoring directories:
rm -rf /root/infrastructure/monitoring 2>/dev/null || true

# Verify free space improvement:
df -h /

echo "COREDB monitoring cleanup complete"
CLEANUP
```

### D.7 Rollback (if AIOPS monitoring becomes insufficient)

```bash
# Step 1: Restart monitoring containers on COREDB:
ssh root@100.118.166.117 "
  cd /root/infrastructure/coredb/monitoring 2>/dev/null && docker compose up -d || {
    echo 'Recreating from backup...'
    # Find compose files in backup:
    ls /root/infrastructure/backups/migration-monitoring-*/
  }
"

# Step 2: Verify monitoring is back:
sleep 10
ssh root@100.118.166.117 "
  docker ps --filter 'name=grafana' --filter 'health=healthy' && echo 'Grafana back' || echo 'Grafana FAIL'
  docker ps --filter 'name=prometheus' && echo 'Prometheus back' || echo 'Prometheus FAIL'
"
```

---

## Specific Service Commands (pre-built, ready to run)

### prediction-radar-worker: EDGE -> AIOPS

```bash
# === PRE-FLIGHT ===
SERVICE="prediction-radar-worker"
ssh root@100.98.163.17 "
  CONTAINERS=\$(docker ps --filter 'name=${SERVICE}' --format '{{.Names}}')
  echo \"Containers: \${CONTAINERS}\"
  for c in \${CONTAINERS}; do
    docker inspect \"\$c\" --format '{{.Name}}: {{.Config.Image}}' >> /tmp/${SERVICE}-images.txt
  done
  COMPOSE_FILE=\$(grep -rl '${SERVICE}' /root/infrastructure/hostinger/ --include='*.yml' | head -1)
  echo \"Compose: \${COMPOSE_FILE}\"
"

# === BACKUP ===
TIMESTAMP=\$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/root/infrastructure/backups/migration-${SERVICE}-\${TIMESTAMP}"
ssh root@100.98.163.17 "
  mkdir -p ${BACKUP_DIR}
  COMPOSE_FILE=\$(grep -rl '${SERVICE}' /root/infrastructure/hostinger/ --include='*.yml' | head -1)
  cp \${COMPOSE_FILE} ${BACKUP_DIR}/
  find \$(dirname \${COMPOSE_FILE}) -maxdepth 1 -name '.env*' -exec cp {} ${BACKUP_DIR}/ \;
  # Commit containers as rollback images:
  for c in \$(docker ps --filter 'name=${SERVICE}' --format '{{.Names}}'); do
    docker commit \"\$c\" \"migration-rollback/\${c}:\${TIMESTAMP}\" 2>/dev/null
  done
  echo 'Backup complete'
"

# === RSYNC STAGING ===
ssh root@100.98.163.17 "
  COMPOSE_FILE=\$(grep -rl '${SERVICE}' /root/infrastructure/hostinger/ --include='*.yml' | head -1)
  SERVICE_DIR=\$(dirname \${COMPOSE_FILE})
  STAGING=/tmp/migration-${SERVICE}-\${TIMESTAMP}
  mkdir -p \${STAGING}
  rsync -avz --delete \
    --exclude='node_modules' --exclude='.venv' --exclude='venv' \
    --exclude='dist' --exclude='build' --exclude='.next' \
    --exclude='cache' --exclude='.cache' \
    --exclude='logs' --exclude='*.log' \
    --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='*.pyo' \
    --exclude='.env' --exclude='.env.local' --exclude='.env.production' \
    --exclude='tmp' --exclude='.tmp' --exclude='coverage' --exclude='.nyc_output' \
    \${SERVICE_DIR}/ \${STAGING}/
  echo \"Staging size: \$(du -sh \${STAGING} | cut -f1)\"
"

# === TRANSFER ===
rsync -avz --delete -e "ssh -o StrictHostKeyChecking=accept-new" \
  root@100.98.163.17:/tmp/migration-${SERVICE}-${TIMESTAMP}/ \
  --rsync-path="mkdir -p /opt/wheeler/migrations/${SERVICE} && rsync" \
  "root@100.121.230.28:/opt/wheeler/migrations/${SERVICE}/"

# === DEPLOY ON AIOPS ===
ssh root@100.121.230.28 "
  cd /opt/wheeler/migrations/${SERVICE}
  docker compose -f docker-compose.yml config > /dev/null && echo 'Compose valid' || exit 1
  docker compose -f docker-compose.yml pull
  docker compose -f docker-compose.yml up -d
  sleep 5
  docker compose -f docker-compose.yml ps
"

# === HEALTH CHECK (60s loop) ===
ssh root@100.121.230.28 "
  ATTEMPT=0
  while [[ \$ATTEMPT -lt 30 ]]; do
    ALL_RUNNING=\$(docker ps --filter 'name=${SERVICE}' --format '{{.Names}}' 2>/dev/null | wc -l)
    if [[ \$ALL_RUNNING -gt 0 ]]; then
      HEALTHY=\$(docker ps --filter 'name=${SERVICE}' --filter 'health=healthy' --format '{{.Names}}' 2>/dev/null | wc -l)
      if [[ \$HEALTHY -eq \$ALL_RUNNING ]]; then
        echo \"ALL HEALTHY\"; exit 0
      fi
    fi
    sleep 2; ATTEMPT=\$((ATTEMPT + 1))
  done
  echo 'HEALTH CHECK TIMEOUT - CHECK LOGS:'
  docker ps -a --filter 'name=${SERVICE}'
  docker logs --tail 30 \$(docker ps -a --filter 'name=${SERVICE}' -q | head -1)
  exit 1
"

# === CUT OVER ===
ssh root@100.98.163.17 "
  COMPOSE_FILE=\$(grep -rl '${SERVICE}' /root/infrastructure/hostinger/ --include='*.yml' | head -1)
  cd \$(dirname \${COMPOSE_FILE})
  docker compose stop '${SERVICE}'
  echo 'EDGE service stopped'
"
# Note: prediction-radar-worker has no public endpoint, no Traefik routing needed.
# Verify it connects to prediction-radar-api and postgres on AIOPS.

# === ROLLBACK ===
ssh root@100.121.230.28 "cd /opt/wheeler/migrations/${SERVICE} && docker compose down --timeout 10"
ssh root@100.98.163.17 "
  COMPOSE_FILE=\$(grep -rl '${SERVICE}' /root/infrastructure/hostinger/ --include='*.yml' | head -1)
  cd \$(dirname \${COMPOSE_FILE})
  docker compose up -d '${SERVICE}'
"
# Verify:
ssh root@100.98.163.17 "docker ps --filter 'name=${SERVICE}' --filter 'health=healthy'"
```

### prediction-radar-scheduler: EDGE -> AIOPS

```bash
# Same pattern as prediction-radar-worker. Substitute SERVICE name:
SERVICE="prediction-radar-scheduler"
# Follow steps above, replacing all occurrences of prediction-radar-worker.
# Key difference: scheduler may have cron expressions in environment variables.
# Verify cron schedule is preserved after migration:
ssh root@100.121.230.28 "
  docker inspect \$(docker ps --filter 'name=${SERVICE}' -q | head -1) \
    --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i cron
"
```

### private-ai-webui: EDGE -> AIOPS

```bash
SERVICE="private-ai-webui"

# Pre-flight: identify port and Traefik routing
ssh root@100.98.163.17 "
  CONTAINER=\$(docker ps --filter 'name=${SERVICE}' --format '{{.Names}}' | head -1)
  if [[ -n \"\${CONTAINER}\" ]]; then
    PORT=\$(docker inspect \"\${CONTAINER}\" --format '{{range \$p,\$c := .NetworkSettings.Ports}}{{(index \$c 0).HostPort}}{{end}}')
    echo \"Service port: \${PORT}\"
    # Check Traefik routing:
    grep -rn \"\${CONTAINER}\" /root/infrastructure/hostinger/traefik/ 2>/dev/null || echo 'No Traefik route found'
  fi
"

# Follow Scenario A steps.

# After cutover, update Traefik on EDGE:
ssh root@100.98.163.17 "
  # Point /private-ai routes to AIOPS:
  sed -i 's|url: \"http://127.0.0.1:<LOCAL_PORT>\"|url: \"http://100.121.230.28:<AIOPS_PORT>\"|g' \
    /root/infrastructure/hostinger/traefik/dynamic.yml
  docker restart traefik
"

# Verify public access:
curl -sf https://<private-ai-domain>.wheeler.ai/ 2>/dev/null && echo "PUBLIC OK" || echo "PUBLIC FAIL"
```

### shared-postgres-recovery: EDGE -> COREDB

```bash
SERVICE="shared-postgres-recovery"

# This is the EDGE postgres that was hosting recovery data.
# Follow Scenario B exactly.

# Additional step: Check which apps reference this postgres:
ssh root@100.98.163.17 "
  PG_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
  echo \"Current connections:\"
  docker exec \"\${PG_CONTAINER}\" psql -U postgres -tAc \
    \"SELECT application_name, client_addr, state, count(*) FROM pg_stat_activity GROUP BY 1,2,3;\" 2>/dev/null
"

# After migration, update all app connection strings:
ssh root@100.121.230.28 "
  find /opt/wheeler/config/envs/ -name '*.env' -print0 | xargs -0 sed -i 's|DATABASE_URL=.*@100.98.163.17|DATABASE_URL=postgresql://user:pass@100.118.166.117|g'
  # Restart dependent services
"
```

### usesend stack: EDGE -> AIOPS (app) + COREDB (MinIO, Redis)

```bash
# Split migration:
#   - usesend app container -> AIOPS (Scenario A)
#   - MinIO (S3-compatible storage) -> COREDB (new Scenario B variant)
#   - Redis (cache/sessions) -> COREDB (new Scenario B variant)

# === PHASE 1: MinIO -> COREDB ===
# Backup MinIO data on EDGE:
ssh root@100.98.163.17 "
  MINIO_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -i minio | head -1)
  VOLUME=\$(docker inspect \"\${MINIO_CONTAINER}\" --format '{{range .Mounts}}{{if eq .Destination \"/data\"}}{{.Source}}{{end}}{{end}}')
  echo \"MinIO volume: \${VOLUME}\"
  BACKUP_DIR=/root/infrastructure/backups/migration-minio-\$(date +%Y%m%d-%H%M%S)
  mkdir -p \${BACKUP_DIR}
  # Use mc (MinIO client) mirror if available, else tar:
  if docker exec \"\${MINIO_CONTAINER}\" mc --version >/dev/null 2>&1; then
    docker exec \"\${MINIO_CONTAINER}\" mc mirror /data/ /tmp/minio-backup/
    docker cp \"\${MINIO_CONTAINER}:/tmp/minio-backup\" \${BACKUP_DIR}/minio-data/
  else
    docker run --rm -v \"\${VOLUME}:/src:ro\" -v \"\${BACKUP_DIR}:/dst\" alpine:latest \
      tar czf /dst/minio-data.tar.gz -C /src .
  fi
  echo \"MinIO backup size: \$(du -sh \${BACKUP_DIR} | cut -f1)\"
"

# Transfer and restore on COREDB:
rsync -avz -e "ssh -o StrictHostKeyChecking=accept-new" \
  root@100.98.163.17:/root/infrastructure/backups/migration-minio-*/ \
  "root@100.118.166.117:/root/infrastructure/backups/migration-minio/"

ssh root@100.118.166.117 "
  # If MinIO container exists, restore data:
  MINIO_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -i minio | head -1)
  if [[ -n \"\${MINIO_CONTAINER}\" ]]; then
    BACKUP_DIR=\$(ls -dt /root/infrastructure/backups/migration-minio-* | head -1)
    if [[ -f \${BACKUP_DIR}/minio-data.tar.gz ]]; then
      VOLUME=\$(docker inspect \"\${MINIO_CONTAINER}\" --format '{{range .Mounts}}{{if eq .Destination \"/data\"}}{{.Source}}{{end}}{{end}}')
      tar xzf \${BACKUP_DIR}/minio-data.tar.gz -C \${VOLUME}/
    else
      docker cp \${BACKUP_DIR}/minio-data/. \"\${MINIO_CONTAINER}:/data/\"
    fi
    echo 'MinIO data restored on COREDB'
  else
    echo 'WARN: No MinIO container on COREDB. Create one first.'
  fi
"

# === PHASE 2: Redis -> COREDB ===
# Follow Scenario B with Redis-specific dump/restore:
ssh root@100.98.163.17 "
  REDIS_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -i redis | head -1)
  docker exec \"\${REDIS_CONTAINER}\" redis-cli BGSAVE
  sleep 5
  BACKUP_DIR=/root/infrastructure/backups/migration-redis-\$(date +%Y%m%d-%H%M%S)
  mkdir -p \${BACKUP_DIR}
  docker cp \"\${REDIS_CONTAINER}:/data/dump.rdb\" \${BACKUP_DIR}/
  echo \"Redis backup: \$(ls -lh \${BACKUP_DIR}/dump.rdb)\"
"

# === PHASE 3: usesend app -> AIOPS ===
# Follow Scenario A exactly.

# === PHASE 4: Update connection strings ===
ssh root@100.121.230.28 "
  # Point Redis to COREDB:
  find /opt/wheeler/config/envs/ -name '.env*' -exec sed -i 's|REDIS_URL=.*@100.98.163.17|REDIS_URL=redis://:password@100.118.166.117:6379|g' {} \;
  # Point S3/MinIO to COREDB:
  find /opt/wheeler/config/envs/ -name '.env*' -exec sed -i 's|S3_ENDPOINT=http://100.98.163.17|S3_ENDPOINT=http://100.118.166.117|g' {} \;
"
```

### temporal-server: EDGE -> AIOPS

```bash
SERVICE="temporal-server"

# Follow Scenario A pattern.
# Temporal has specific health endpoints:
ssh root@100.121.230.28 "
  # Temporal health: check all services are up
  docker exec \$(docker ps --filter 'name=temporal' -q | head -1) \
    tctl --address localhost:7233 cluster health 2>/dev/null || echo 'tctl not available'
  # Alternative: check gRPC health
  grpcurl -plaintext localhost:7233 list 2>/dev/null || echo 'grpcurl not available'
"

# If Temporal uses a database, ensure DB connection follows to COREDB:
ssh root@100.121.230.28 "
  docker inspect \$(docker ps --filter 'name=temporal' -q | head -1) \
    --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -iE 'DB|SQL|POSTGRES|MYSQL'
"

# Temporal workers may also need migration (follow PM2 or Docker scenario as applicable).
```

### COREDB Monitoring Consolidation

```bash
# This follows Scenario D exactly. Key commands for reference:

# 1. Verify AIOPS monitoring is ready:
ssh root@100.121.230.28 "
  curl -sf http://127.0.0.1:9090/api/v1/targets | python3 -m json.tool | grep -E '100.118.166.117' || echo 'Add COREDB targets to AIOPS Prometheus first'
"

# 2. Stop Grafana/Loki/Prometheus on COREDB:
ssh root@100.118.166.117 "
  for c in \$(docker ps --format '{{.Names}}' | grep -iE 'grafana|prometheus|loki|alertmanager|netdata'); do
    docker stop \"\$c\" 2>/dev/null && echo \"Stopped \$c\"
  done
"

# 3. Keep exporters running:
ssh root@100.118.166.117 "
  docker ps --format '{{.Names}} {{.Status}}' | grep -iE 'exporter|node_export'
"

# 4. Verify AIOPS sees COREDB:
ssh root@100.121.230.28 "
  curl -sf 'http://127.0.0.1:9090/api/v1/query?query=up{instance=~".*100.118.166.117.*"}' | head -50
"

# 5. After 7 days of stable operation, remove stopped containers from COREDB:
ssh root@100.118.166.117 "
  for c in \$(docker ps -a --format '{{.Names}}' | grep -iE 'grafana|prometheus|loki|alertmanager'); do
    docker rm \"\$c\" && echo \"Removed \$c\"
  done
"
```

---

## Rollback Post-Mortem Template

After any rollback, document:

```markdown
## Rollback: [SERVICE] [DATE]

**Migration:** EDGE -> [AIOPS|COREDB]
**Started:** [time] UTC
**Rollback Started:** [time] UTC
**Rollback Complete:** [time] UTC
**Total Downtime:** [duration]

**Trigger:** [health check failure / error rate / etc.]

**Root Cause:** [brief]

**Data Loss:** [YES/NO - scope if yes]

**Commands Executed:** [paste exact commands that worked]

**What Went Wrong:** [technical details]

**Prevention:**
- [ ] [action item]
```

---

## Post-Migration Cleanup (run after 7 days of stable operation)

```bash
# On EDGE - Remove decommissioned containers and images:
ssh root@100.98.163.17 "
  # Remove stopped containers older than 7 days:
  docker container prune -f --filter 'until=168h'
  # Remove migration rollback images:
  docker images 'migration-rollback/*' --format '{{.Repository}}:{{.Tag}}' | xargs -r docker rmi
  # Remove migration backups older than 30 days:
  find /root/infrastructure/backups/migration-* -maxdepth 0 -mtime +30 -exec rm -rf {} \;
"

# On AIOPS - Remove migration staging directories:
ssh root@100.121.230.28 "
  find /opt/wheeler/migrations -maxdepth 1 -mtime +7 -exec rm -rf {} \;
  find /tmp/migration-* -maxdepth 0 -mtime +7 -exec rm -rf {} \;
"

# On COREDB - Remove migration backup artifacts:
ssh root@100.118.166.117 "
  find /root/infrastructure/backups/migration-* -maxdepth 0 -mtime +30 -exec rm -rf {} \;
  echo 'COREDB cleanup complete'
"
```
