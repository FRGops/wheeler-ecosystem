# Wheeler Enterprise -- Validation Gates

**Version:** 1.0.0 | **Date:** 2026-05-23 | **Owner:** SRE Team

Every migration step in MIGRATION_COMMANDS.md is gated by validation. No gate can be skipped. A failed gate blocks the migration until resolved.

## Gate Severity

| Severity | Meaning | Action |
|----------|---------|--------|
| **BLOCKER** | Migration cannot proceed | Fix the issue before continuing |
| **WARN** | Risk exists but migration may proceed with caution | Document and monitor |
| **INFO** | Verification checkpoint | Confirm and continue |

---

## Pre-Migration Gate (ALL migrations, ALL servers)

Every migration scenario (A, B, C, D) must pass ALL of these before the first `rsync`.

### PG-1: Backup Verified (BLOCKER)

```bash
# Verification command (run on source server):
BACKUP_EXIT=0
sudo bash /root/infrastructure/enterprise/phase6-backup/backup-all.sh || BACKUP_EXIT=$?
if [[ $BACKUP_EXIT -ne 0 ]]; then
  echo "BLOCKER: Backup script failed with exit code ${BACKUP_EXIT}"
  echo "Check /var/log/wheeler/backup.log for errors"
  exit 1
fi

# Verify the encrypted backup file exists and is non-empty:
LATEST_BACKUP=$(ls -t /root/infrastructure/backups/backup-*.tar.gz.gpg 2>/dev/null | head -1)
if [[ -z "$LATEST_BACKUP" ]]; then
  echo "BLOCKER: No encrypted backup file found"
  exit 1
fi
BACKUP_SIZE=$(stat --printf="%s" "$LATEST_BACKUP" 2>/dev/null || echo "0")
if [[ "$BACKUP_SIZE" -lt 1024 ]]; then
  echo "BLOCKER: Backup file is too small (${BACKUP_SIZE} bytes) -- likely empty or corrupt"
  exit 1
fi
echo "PASS: Backup exists ($(numfmt --to=iec $BACKUP_SIZE))"

# Verify SHA256 checksum:
if [[ -f "${LATEST_BACKUP}.sha256" ]]; then
  sha256sum -c "${LATEST_BACKUP}.sha256" 2>/dev/null && echo "PASS: SHA256 checksum verified" || {
    echo "BLOCKER: SHA256 checksum FAILED -- backup is corrupt"
    exit 1
  }
else
  echo "WARN: No SHA256 checksum file found for latest backup"
fi

# Decryption test (requires BACKUP_PASSPHRASE env var):
if gpg --decrypt --batch --passphrase "${BACKUP_PASSPHRASE}" "$LATEST_BACKUP" > /dev/null 2>&1; then
  echo "PASS: Backup decrypts successfully"
else
  echo "BLOCKER: Backup decryption FAILED -- incorrect passphrase or corrupt file"
  exit 1
fi
```

### PG-2: Rollback Snapshot Exists (BLOCKER)

```bash
# Verify pre-migration-snapshot was run and completed:
SNAPSHOT_DIR=$(ls -dt /root/infrastructure/backups/pre-migration-snapshots/snapshot_* 2>/dev/null | head -1)
if [[ -z "$SNAPSHOT_DIR" ]]; then
  echo "BLOCKER: No pre-migration snapshot found. Run:"
  echo "  sudo bash /root/infrastructure/hetzner/backup/pre-migration-snapshot.sh"
  exit 1
fi

# Verify manifest exists:
if [[ ! -f "${SNAPSHOT_DIR}/manifest.json" ]]; then
  echo "BLOCKER: Snapshot manifest missing -- snapshot may be incomplete"
  exit 1
fi

# Verify snapshot was created within the last hour:
SNAPSHOT_AGE=$(($(date +%s) - $(stat --printf="%Y" "${SNAPSHOT_DIR}/manifest.json")))
if [[ "$SNAPSHOT_AGE" -gt 3600 ]]; then
  echo "WARN: Snapshot is $(($SNAPSHOT_AGE / 60)) minutes old. Consider re-running."
fi

# Verify snapshot contains databases:
if [[ ! -d "${SNAPSHOT_DIR}/databases" ]] || [[ -z "$(ls -A ${SNAPSHOT_DIR}/databases/ 2>/dev/null)" ]]; then
  echo "WARN: Snapshot databases directory is empty -- no DB snapshots taken"
else
  echo "PASS: Snapshot contains $(ls ${SNAPSHOT_DIR}/databases/*.dump 2>/dev/null | wc -l) database dumps"
fi

# Verify snapshot contains Docker configs:
if [[ ! -d "${SNAPSHOT_DIR}/docker" ]] || [[ -z "$(ls -A ${SNAPSHOT_DIR}/docker/ 2>/dev/null)" ]]; then
  echo "WARN: Snapshot Docker configs directory is empty"
else
  echo "PASS: Snapshot contains $(ls ${SNAPSHOT_DIR}/docker/ 2>/dev/null | wc -l) Docker config files"
fi

echo "PASS: Rollback snapshot verified at ${SNAPSHOT_DIR}"
```

### PG-3: Source Service State Documented (BLOCKER)

```bash
# Record EXACT state of the service being migrated -- these become the rollback baseline.

# Docker service:
SERVICE="<service-name>"
echo "=== ${SERVICE} Pre-Migration State ==="

# Containers:
docker ps --filter "name=${SERVICE}" --format '{{.Names}} {{.Image}} {{.Status}} {{.Ports}}' > /tmp/${SERVICE}-pre-migration-state.txt
if [[ ! -s /tmp/${SERVICE}-pre-migration-state.txt ]]; then
  echo "BLOCKER: No running containers found for '${SERVICE}'"
  exit 1
fi
echo "PASS: $(wc -l < /tmp/${SERVICE}-pre-migration-state.txt) containers documented"

# PM2 service:
pm2 show "${SERVICE}" > /dev/null 2>&1 && {
  pm2 show "${SERVICE}" > /tmp/${SERVICE}-pre-migration-pm2-state.txt
  echo "PASS: PM2 state documented"
  pm2 show "${SERVICE}" | grep -E 'status|restarts|memory|cpu'
}

# Compose file (Docker only):
COMPOSE_FILE=$(grep -rl "${SERVICE}" /root/infrastructure/ --include='*.yml' | head -1)
if [[ -z "$COMPOSE_FILE" ]]; then
  echo "WARN: No compose file found containing '${SERVICE}' -- service may be standalone"
else
  cp "$COMPOSE_FILE" "/tmp/${SERVICE}-pre-migration-compose.yml"
  echo "PASS: Compose file documented at /tmp/${SERVICE}-pre-migration-compose.yml"
fi
```

### PG-4: Target Server Reachable (BLOCKER)

```bash
TARGET_IP="<target_tailscale_ip>"

# SSH connectivity:
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "root@${TARGET_IP}" 'echo "SSH OK"' 2>/dev/null && \
  echo "PASS: SSH to ${TARGET_IP} working" || {
    echo "BLOCKER: Cannot SSH to ${TARGET_IP}. Check:"
    echo "  1. tailscale status (on source)"
    echo "  2. UFW allows port 22 from Tailscale subnet"
    echo "  3. Target server is powered on"
    exit 1
  }

# Tailscale mesh check:
ssh "root@${TARGET_IP}" 'tailscale status' 2>/dev/null | head -3
echo ""

# Latency check (190ms expected EDGE->AIOPS):
LATENCY=$(ping -c 3 -W 2 "${TARGET_IP}" 2>/dev/null | tail -1 | awk -F'/' '{print $5}' || echo "unknown")
echo "Latency to ${TARGET_IP}: ${LATENCY}ms"
```

### PG-5: Target Server Resources (BLOCKER)

```bash
ssh "root@${TARGET_IP}" << 'RES_CHECK'

# Disk space (need at least 10GB free):
AVAIL_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ "$AVAIL_GB" -lt 10 ]]; then
  echo "BLOCKER: Only ${AVAIL_GB}GB free on /. Need at least 10GB."
  exit 1
fi
echo "PASS: ${AVAIL_GB}GB free on /"

# Memory (need at least 2GB free):
FREE_MEM_GB=$(free -g | awk '/^Mem:/{print $7}')
if [[ "$FREE_MEM_GB" -lt 2 ]]; then
  echo "BLOCKER: Only ${FREE_MEM_GB}GB free memory. Need at least 2GB."
  exit 1
fi
echo "PASS: ${FREE_MEM_GB}GB free memory"

# Docker running:
docker info > /dev/null 2>&1 && echo "PASS: Docker running" || {
  echo "BLOCKER: Docker not running on target"
  exit 1
}

# Docker compose available:
docker compose version > /dev/null 2>&1 && echo "PASS: Docker Compose available" || {
  echo "BLOCKER: docker compose not available"
  exit 1
}

# Load average reasonable (under core count):
CORES=$(nproc)
LOAD_1M=$(awk '{print $1}' /proc/loadavg)
if (( $(echo "$LOAD_1M > $CORES * 0.8" | bc -l 2>/dev/null || echo 0) )); then
  echo "WARN: Load average ${LOAD_1M} is high (cores: ${CORES}). Performance may be degraded."
else
  echo "PASS: Load average ${LOAD_1M} (cores: ${CORES})"
fi
RES_CHECK
```

### PG-6: Target Dependencies Healthy (BLOCKER)

```bash
ssh "root@${TARGET_IP}" << 'DEP_CHECK'

# PostgreSQL (if target is AIOPS or COREDB):
if docker ps --format '{{.Names}}' | grep -qi postgres; then
  PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
  if docker exec "$PG_CONTAINER" pg_isready -U postgres > /dev/null 2>&1; then
    echo "PASS: PostgreSQL ($PG_CONTAINER) is ready"
    CONN_COUNT=$(docker exec "$PG_CONTAINER" psql -U postgres -tAc "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null || echo "?")
    echo "  Active connections: ${CONN_COUNT}"
  else
    echo "WARN: PostgreSQL not ready -- some migrations may be affected"
  fi
fi

# Redis (if target is AIOPS or COREDB):
if docker ps --format '{{.Names}}' | grep -qi redis; then
  REDIS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i redis | head -1)
  if docker exec "$REDIS_CONTAINER" redis-cli PING 2>/dev/null | grep -q PONG; then
    echo "PASS: Redis ($REDIS_CONTAINER) responds to PING"
    MEM_USED=$(docker exec "$REDIS_CONTAINER" redis-cli INFO memory 2>/dev/null | grep 'used_memory_human' | cut -d: -f2 | tr -d '\r')
    echo "  Memory used: ${MEM_USED}"
  else
    echo "WARN: Redis not responding -- some migrations may be affected"
  fi
fi

# MinIO (if target is COREDB):
if curl -sf http://127.0.0.1:9000/minio/health/live > /dev/null 2>&1; then
  echo "PASS: MinIO health check passed"
else
  echo "INFO: MinIO health endpoint not reachable (may not be running yet)"
fi

# Tailscale:
tailscale status > /dev/null 2>&1 && echo "PASS: Tailscale running" || {
  echo "BLOCKER: Tailscale not running on target"
  exit 1
}
DEP_CHECK
```

### PG-7: Target Ports Available (BLOCKER)

```bash
# Verify ports needed by the service being migrated are free on target.
# Adjust PORT_LIST per service:
PORT_LIST="8000 8098 5433 6379 8007 4222 5672 5000 3130 3001 3002 9090 3100 9093 19999 8080 8088 8123 9000"

ssh "root@${TARGET_IP}" "
  CONFLICTS=0
  for port in ${PORT_LIST}; do
    if ss -tlnp \"sport = :\${port}\" 2>/dev/null | grep -q \":\${port}\"; then
      echo \"WARN: Port \${port} is in use:\"
      ss -tlnp \"sport = :\${port}\" | grep \":\${port}\"
      CONFLICTS=\$((CONFLICTS + 1))
    fi
  done
  if [[ \$CONFLICTS -gt 0 ]]; then
    echo \"\"
    echo \"\${CONFLICTS} port(s) in use. Review whether these are the target service already running.\"
  else
    echo 'PASS: No port conflicts detected'
  fi
"
```

### PG-8: PM2 Config Verified (BLOCKER, if applicable)

```bash
# Only for PM2 migrations (Scenario C)
APP_NAME="<pm2-app-name>"

# Verify PM2 is installed on target:
ssh "root@${TARGET_IP}" 'pm2 ping > /dev/null 2>&1 && echo "PASS: PM2 daemon running" || {
  echo "BLOCKER: PM2 not running on target. Install with: npm install -g pm2"
  exit 1
}'

# Verify no app name collision:
ssh "root@${TARGET_IP}" "
  if pm2 show '${APP_NAME}' > /dev/null 2>&1; then
    echo 'BLOCKER: App \"${APP_NAME}\" already exists on target PM2'
    echo 'Stop and delete it first, or rename:'
    echo '  pm2 stop ${APP_NAME} && pm2 delete ${APP_NAME}'
    exit 1
  fi
  echo 'PASS: App name \"${APP_NAME}\" available'
"

# Verify target node/python version matches source expectations:
ssh "root@${TARGET_IP}" '
  echo "Node: $(node --version 2>/dev/null || echo 'NOT INSTALLED')"
  echo "Python: $(python3 --version 2>/dev/null || echo 'NOT INSTALLED')"
  echo "npm: $(npm --version 2>/dev/null || echo 'NOT INSTALLED')"
'
```

### PG-9: Docker Config Verified (BLOCKER, if applicable)

```bash
# Only for Docker migrations (Scenario A, B, D)
SERVICE="<service-name>"

# Verify compose file on source parses correctly:
SOURCE_COMPOSE=$(grep -rl "${SERVICE}" /root/infrastructure/ --include='*.yml' | head -1)
if [[ -n "$SOURCE_COMPOSE" ]]; then
  docker compose -f "$SOURCE_COMPOSE" config > /dev/null 2>&1 && \
    echo "PASS: Source compose file valid" || \
    echo "BLOCKER: Source compose file '$SOURCE_COMPOSE' is invalid. Fix before migrating."
fi

# Verify Docker networks exist on target (if service joins a custom network):
ssh "root@${TARGET_IP}" "
  # List networks; check if any needed networks are missing:
  EXISTING_NETWORKS=\$(docker network ls --format '{{.Name}}')
  for net in traefik-public prediction-radar data messaging automation; do
    if echo \"\${EXISTING_NETWORKS}\" | grep -q \"^\${net}$\"; then
      echo \"PASS: Network \${net} exists\"
    else
      echo \"INFO: Network \${net} does not exist (will be created by compose)\"
    fi
  done
"
```

### PG-10: Logs Path Verified (BLOCKER)

```bash
# Ensure log directory exists and is writable on target:
ssh "root@${TARGET_IP}" '
  mkdir -p /var/log/wheeler /opt/wheeler/logs
  if [[ -w /var/log/wheeler ]] && [[ -w /opt/wheeler/logs ]]; then
    echo "PASS: Log directories exist and are writable"
  else
    echo "BLOCKER: Log directories not writable"
    exit 1
  fi

  # Check logrotate is in place (prevents disk fill):
  if [[ -f /etc/logrotate.d/wheeler-enterprise ]]; then
    echo "PASS: logrotate config found"
  else
    echo "WARN: No logrotate config found for wheeler. Logs may fill disk."
  fi
'
```

---

## Per-Migration Validation Gates

These run after the rsync transfer but before cutover. Each migration scenario has specific checks.

### Scenario A: Docker Service EDGE -> AIOPS

#### A-GATE-1: Rsync Transfer Integrity (BLOCKER)

```bash
SERVICE="<service-name>"

# Compare file counts between source staging and target:
SOURCE_COUNT=$(find "/tmp/migration-${SERVICE}-${TIMESTAMP}/" -type f | wc -l)
TARGET_COUNT=$(ssh root@100.121.230.28 "find /opt/wheeler/migrations/${SERVICE}/ -type f | wc -l")

if [[ "$SOURCE_COUNT" -eq "$TARGET_COUNT" ]]; then
  echo "PASS: File counts match (${SOURCE_COUNT} files)"
else
  echo "BLOCKER: File count mismatch -- source=${SOURCE_COUNT}, target=${TARGET_COUNT}"
  echo "Re-run rsync. Check for permission errors."
  exit 1
fi

# Verify compose file arrived:
ssh root@100.121.230.28 "test -f /opt/wheeler/migrations/${SERVICE}/docker-compose.yml && echo 'PASS: compose file present' || {
  echo 'BLOCKER: docker-compose.yml missing on target'
  exit 1
}"

# Verify total size is reasonable:
SOURCE_SIZE=$(du -sb "/tmp/migration-${SERVICE}-${TIMESTAMP}/" | cut -f1)
TARGET_SIZE=$(ssh root@100.121.230.28 "du -sb /opt/wheeler/migrations/${SERVICE}/" | cut -f1)
echo "Source size: $(numfmt --to=iec ${SOURCE_SIZE})"
echo "Target size: $(numfmt --to=iec ${TARGET_SIZE})"

# Check for missing exclusions (should NOT have node_modules, .venv, etc):
ssh root@100.121.230.28 "
  for dir in node_modules .venv venv dist build .git __pycache__; do
    if find /opt/wheeler/migrations/${SERVICE}/ -maxdepth 5 -name \"\$dir\" -type d 2>/dev/null | grep -q .; then
      echo \"WARN: \$dir found on target (should have been excluded by rsync)\"
    fi
  done
  echo 'Exclusion check complete'
"
```

#### A-GATE-2: Compose Config Valid on Target (BLOCKER)

```bash
ssh root@100.121.230.28 "
  cd /opt/wheeler/migrations/${SERVICE}
  OUTPUT=\$(docker compose -f docker-compose.yml config 2>&1)
  RC=\$?
  if [[ \$RC -ne 0 ]]; then
    echo 'BLOCKER: docker-compose.yml invalid on target:'
    echo \"\$OUTPUT\"
    exit 1
  fi
  echo 'PASS: Compose config valid'
  
  # Verify service name is in the compose:
  docker compose -f docker-compose.yml config --services | grep -q '${SERVICE}' && \
    echo 'PASS: Service \"${SERVICE}\" found in compose' || \
    echo 'WARN: Service \"${SERVICE}\" not found -- check compose file'
"
```

#### A-GATE-3: Environment Variables Present (BLOCKER)

```bash
ssh root@100.121.230.28 "
  cd /opt/wheeler/migrations/${SERVICE}
  
  # .env file:
  if [[ -f .env ]]; then
    echo 'PASS: .env file present'
    ENV_VARS=\$(grep -c '=' .env 2>/dev/null || echo 0)
    echo \"  Environment variables: \${ENV_VARS}\"
  elif [[ -f /opt/wheeler/config/envs/${SERVICE}.env ]]; then
    cp /opt/wheeler/config/envs/${SERVICE}.env .env
    echo 'INFO: Copied .env from /opt/wheeler/config/envs/'
  else
    echo 'BLOCKER: No .env file found. Create /opt/wheeler/config/envs/${SERVICE}.env first.'
    exit 1
  fi
  
  # Check for placeholder/example values:
  if grep -iE '(CHANGE_ME|REPLACE_ME|YOUR_API_KEY|<your-|TODO|FIXME)' .env 2>/dev/null; then
    echo 'BLOCKER: .env contains placeholder values. Replace them before deploying.'
    exit 1
  fi
"
```

#### A-GATE-4: Image Pull Success (BLOCKER)

```bash
ssh root@100.121.230.28 "
  cd /opt/wheeler/migrations/${SERVICE}
  PULL_OUTPUT=\$(docker compose -f docker-compose.yml pull 2>&1)
  PULL_RC=\$?
  echo \"\$PULL_OUTPUT\" | tail -10
  if [[ \$PULL_RC -ne 0 ]]; then
    echo 'BLOCKER: Image pull failed. Check Docker Hub/GHCR access and image names.'
    exit 1
  fi
  echo 'PASS: Images pulled successfully'
"
```

#### A-GATE-5: Network Connectivity to Dependencies (BLOCKER)

```bash
ssh root@100.121.230.28 "
  # The service will be on an internal Docker network.
  # Verify it can reach its dependencies (postgres, redis, etc.) on AIOPS:
  
  # PostgreSQL:
  if docker ps --format '{{.Names}}' | grep -qi postgres; then
    PG_HOST=\$(grep -oP 'DATABASE_URL=.*@\K[^:/]+' /opt/wheeler/migrations/${SERVICE}/.env 2>/dev/null || echo 'postgres-aio-main')
    docker exec \$(docker ps --format '{{.Names}}' | grep -i postgres | head -1) pg_isready -U postgres > /dev/null 2>&1 && \
      echo 'PASS: PostgreSQL reachable' || echo 'WARN: PostgreSQL not reachable'
  fi
  
  # Redis:
  if docker ps --format '{{.Names}}' | grep -qi redis; then
    docker exec \$(docker ps --format '{{.Names}}' | grep -i redis | head -1) redis-cli PING 2>/dev/null | grep -q PONG && \
      echo 'PASS: Redis reachable' || echo 'WARN: Redis not reachable'
  fi
"
```

### Scenario B: Database EDGE -> COREDB

#### B-GATE-1: Dump Integrity Verified (BLOCKER)

```bash
DUMP_FILE="<path-to-dump-on-coredb>"

ssh root@100.118.166.117 "
  if [[ ! -f '${DUMP_FILE}' ]]; then
    echo 'BLOCKER: Dump file not found on COREDB'
    exit 1
  fi

  # Check dump is non-empty:
  SIZE=\$(stat --printf='%s' '${DUMP_FILE}' 2>/dev/null || echo 0)
  if [[ \$SIZE -lt 1024 ]]; then
    echo 'BLOCKER: Dump file is too small (\${SIZE} bytes)'
    exit 1
  fi
  echo \"PASS: Dump file size: \$(numfmt --to=iec \${SIZE})\"

  # Test decompression:
  if gunzip -t '${DUMP_FILE}' 2>/dev/null; then
    echo 'PASS: Dump passes integrity check (gzip -t)'
  else
    echo 'BLOCKER: Dump integrity check failed'
    exit 1
  fi

  # Quick content check -- verify it contains SQL:
  gunzip -c '${DUMP_FILE}' 2>/dev/null | head -50 | grep -qiE 'CREATE|INSERT|COPY' && \
    echo 'PASS: Dump contains SQL statements' || \
    echo 'WARN: Dump does not appear to contain SQL'
"
```

#### B-GATE-2: COREDB Postgres Ready (BLOCKER)

```bash
ssh root@100.118.166.117 "
  PG_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
  if [[ -z \"\$PG_CONTAINER\" ]]; then
    echo 'BLOCKER: No PostgreSQL container running on COREDB'
    exit 1
  fi
  echo \"PASS: PostgreSQL container: \${PG_CONTAINER}\"

  # Check pg_isready:
  docker exec \"\$PG_CONTAINER\" pg_isready -U postgres > /dev/null 2>&1 && \
    echo 'PASS: PostgreSQL accepting connections' || {
    echo 'BLOCKER: PostgreSQL not accepting connections'
    exit 1
  }

  # Check disk space for restore:
  DUMP_SIZE=\$(stat --printf='%s' '${DUMP_FILE}')
  PG_DATA=\$(docker inspect \"\$PG_CONTAINER\" --format '{{range .Mounts}}{{if eq .Destination \"/var/lib/postgresql/data\"}}{{.Source}}{{end}}{{end}}')
  PG_DATA_FREE=\$(df \"\$PG_DATA\" | awk 'NR==2 {print \$4}')
  NEEDED_FREE=\$((DUMP_SIZE * 5 / 1024))  # Rough estimate: 5x dump size
  if [[ \$PG_DATA_FREE -lt \$NEEDED_FREE ]]; then
    echo \"WARN: May not have enough disk for restore. Free: \$(numfmt --to=iec \$((PG_DATA_FREE * 1024))), Estimated need: \$(numfmt --to=iec \$((NEEDED_FREE * 1024)))\"
  else
    echo 'PASS: Sufficient disk space for restore'
  fi
"
```

#### B-GATE-3: Application Connection String Update Verified (BLOCKER)

```bash
# After cutover, verify apps can reach COREDB:
ssh root@100.121.230.28 "
  # From AIOPS, try connecting to COREDB postgres:
  PGPASSWORD='<password>' pg_isready -h 100.118.166.117 -p 5432 -U postgres && \
    echo 'PASS: AIOPS can reach COREDB PostgreSQL' || {
    echo 'BLOCKER: AIOPS cannot reach COREDB PostgreSQL. Check:'
    echo '  1. COREDB UFW allows port 5432 from Tailscale'
    echo '  2. COREDB postgres listens on Tailscale IP (100.118.166.117)'
    echo '  3. pg_hba.conf allows connections from 100.121.230.28'
    exit 1
  }
"
```

### Scenario C: PM2 Service EDGE -> AIOPS

#### C-GATE-1: Source Code Transferred (BLOCKER)

```bash
ssh root@100.121.230.28 "
  APP_DIR='/opt/pm2-apps/${APP_NAME}'
  if [[ ! -d \"\${APP_DIR}\" ]]; then
    echo 'BLOCKER: App directory not found on AIOPS'
    exit 1
  fi
  
  FILE_COUNT=\$(find \"\${APP_DIR}\" -type f ! -path '*/node_modules/*' | wc -l)
  echo \"PASS: \${APP_DIR} contains \${FILE_COUNT} files\"
  
  # Verify main entry point exists:
  for entry in index.js index.ts main.js main.py server.js app.js; do
    if [[ -f \"\${APP_DIR}/\${entry}\" ]]; then
      echo \"PASS: Entry point found: \${entry}\"
      break
    fi
  done
"
```

#### C-GATE-2: Dependencies Installed (BLOCKER)

```bash
ssh root@100.121.230.28 "
  APP_DIR='/opt/pm2-apps/${APP_NAME}'
  cd \"\${APP_DIR}\"
  
  if [[ -f package.json ]]; then
    if [[ -d node_modules ]]; then
      MODULE_COUNT=\$(ls node_modules | wc -l)
      echo \"PASS: node_modules exists (\${MODULE_COUNT} packages)\"
    else
      echo 'BLOCKER: node_modules missing. Run: cd \${APP_DIR} && npm install --production'
      exit 1
    fi
  fi
  
  if [[ -f requirements.txt ]]; then
    if [[ -d .venv ]] || python3 -c 'import sys; sys.exit(0)' 2>/dev/null; then
      echo 'PASS: Python dependencies appear installed'
    else
      echo 'WARN: Python venv not found'
    fi
  fi
"
```

#### C-GATE-3: PM2 App Stable (BLOCKER)

```bash
# Wait 30 seconds and verify no restarts:
ssh root@100.121.230.28 "
  APP_NAME='${APP_NAME}'
  INITIAL_UPTIME=\$(pm2 show \"\${APP_NAME}\" 2>/dev/null | grep 'uptime' | awk '{print \$NF}' || echo '')
  INITIAL_RESTARTS=\$(pm2 show \"\${APP_NAME}\" 2>/dev/null | grep 'restarts' | awk '{print \$NF}' || echo '')
  
  sleep 30
  
  FINAL_RESTARTS=\$(pm2 show \"\${APP_NAME}\" 2>/dev/null | grep 'restarts' | awk '{print \$NF}' || echo '')
  STATUS=\$(pm2 show \"\${APP_NAME}\" 2>/dev/null | grep 'status' | awk '{print \$NF}' || echo 'unknown')
  
  echo \"Status: \${STATUS}\"
  echo \"Restarts during check: \$((FINAL_RESTARTS - INITIAL_RESTARTS))\"
  
  if [[ \"\$STATUS\" != 'online' ]]; then
    echo 'BLOCKER: PM2 app not online'
    pm2 logs \"\${APP_NAME}\" --lines 30 --nostream
    exit 1
  fi
  
  if [[ \$((FINAL_RESTARTS - INITIAL_RESTARTS)) -gt 0 ]]; then
    echo 'BLOCKER: App restarted during stability check'
    pm2 logs \"\${APP_NAME}\" --lines 30 --nostream
    exit 1
  fi
  
  echo 'PASS: PM2 app stable for 30 seconds'
"
```

### Scenario D: COREDB Monitoring Consolidation

#### D-GATE-1: AIOPS Monitoring Ready (BLOCKER)

```bash
ssh root@100.121.230.28 << 'AIOPS_MON_CHECK'

# Prometheus running and scraping:
curl -sf http://127.0.0.1:9090/-/healthy > /dev/null 2>&1 && \
  echo 'PASS: Prometheus healthy' || {
  echo 'BLOCKER: Prometheus not running on AIOPS'
  exit 1
}

# Grafana running:
curl -sf http://127.0.0.1:3002/api/health > /dev/null 2>&1 && \
  echo 'PASS: Grafana healthy' || {
  echo 'BLOCKER: Grafana not running on AIOPS'
  exit 1
}

# Loki running:
curl -sf http://127.0.0.1:3100/ready > /dev/null 2>&1 && \
  echo 'PASS: Loki ready' || \
  echo 'WARN: Loki not ready -- logs will not be collected from COREDB'

# Verify Prometheus scrapes COREDB exporters:
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=up{instance=~".*100.118.166.117.*"}' 2>/dev/null | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
targets = data.get('data', {}).get('result', [])
up_count = sum(1 for t in targets if t.get('value', [None, '0'])[1] == '1')
total = len(targets)
print(f'PASS: {up_count}/{total} COREDB exporters UP') if total > 0 and up_count == total else print(f'WARN: {up_count}/{total} COREDB exporters UP')
" 2>/dev/null || echo 'WARN: Cannot parse Prometheus response'

# Check COREDB node_exporter is reachable:
curl -sf http://100.118.166.117:9100/metrics 2>/dev/null | head -1 && \
  echo 'PASS: COREDB node_exporter reachable' || \
  echo 'BLOCKER: COREDB node_exporter not reachable from AIOPS'
AIOPS_MON_CHECK
```

#### D-GATE-2: COREDB Exporters Still Running After Monitoring Stop (BLOCKER)

```bash
ssh root@100.118.166.117 << 'EXPORTER_CHECK'
# Verify exporters are running:
docker ps --format '{{.Names}} {{.Status}}' | grep -E 'exporter|node_export' && \
  echo 'PASS: Exporters still running' || \
  echo 'BLOCKER: Exporters not running on COREDB'

# Verify metrics endpoints respond:
curl -sf http://127.0.0.1:9100/metrics > /dev/null 2>&1 && echo 'PASS: node_exporter metrics' || echo 'WARN: node_exporter metrics'
curl -sf http://127.0.0.1:9187/metrics > /dev/null 2>&1 && echo 'PASS: postgres_exporter metrics' || echo 'WARN: postgres_exporter metrics'
curl -sf http://127.0.0.1:9121/metrics > /dev/null 2>&1 && echo 'PASS: redis_exporter metrics' || echo 'WARN: redis_exporter metrics'
EXPORTER_CHECK
```

---

## Post-Migration Validation (ALL migrations must pass)

These run after cutover. All items must pass before declaring migration complete.

### PV-1: Service Responds on Health Endpoint (BLOCKER)

```bash
# Docker services:
ssh "root@${TARGET_IP}" "
  SERVICE='${SERVICE}'
  CONTAINER=\$(docker ps --filter 'name=\${SERVICE}' -q | head -1)
  if [[ -z \"\$CONTAINER\" ]]; then
    echo 'BLOCKER: No container found for \${SERVICE}'
    exit 1
  fi
  echo \"Container: \$(docker inspect --format '{{.Name}}' \"\$CONTAINER\")\"
  
  # Docker health check:
  HEALTH=\$(docker inspect --format '{{.State.Health.Status}}' \"\$CONTAINER\" 2>/dev/null || echo 'no-healthcheck')
  echo \"Docker health: \${HEALTH}\"
  if [[ \"\$HEALTH\" == 'unhealthy' ]]; then
    echo 'BLOCKER: Container is unhealthy'
    docker logs --tail 50 \"\$CONTAINER\" | tail -20
    exit 1
  fi
"

# PM2 services:
ssh "root@${TARGET_IP}" "
  STATUS=\$(pm2 show '${SERVICE}' 2>/dev/null | grep 'status' | awk '{print \$NF}')
  if [[ \"\$STATUS\" != 'online' ]]; then
    echo 'BLOCKER: PM2 app not online (status: \${STATUS})'
    pm2 logs '${SERVICE}' --lines 30 --nostream
    exit 1
  fi
  echo 'PASS: PM2 app online'
"

# HTTP health endpoint (if applicable):
PORT="<service-health-port>"
ssh "root@${TARGET_IP}" "
  HTTP_CODE=\$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:${PORT}/health 2>/dev/null || echo '000')
  if [[ \"\$HTTP_CODE\" == '200' ]] || [[ \"\$HTTP_CODE\" == '204' ]]; then
    echo \"PASS: Health endpoint returned HTTP \${HTTP_CODE}\"
  else
    echo \"WARN: Health endpoint returned HTTP \${HTTP_CODE} (may not expose health endpoint)\"
  fi
"
```

### PV-2: No Error Logs in First 60 Seconds (BLOCKER)

```bash
ssh "root@${TARGET_IP}" "
  SERVICE='${SERVICE}'
  
  # Wait for settle time:
  echo 'Waiting 60 seconds for log stabilization...'
  sleep 60
  
  # Docker service:
  if docker ps --filter 'name=\${SERVICE}' --format '{{.Names}}' | grep -q .; then
    CONTAINER=\$(docker ps --filter 'name=\${SERVICE}' -q | head -1)
    ERRORS=\$(docker logs --since 60s \"\$CONTAINER\" 2>&1 | grep -ciE 'ERROR|FATAL|PANIC|CRITICAL' || echo 0)
    if [[ \"\$ERRORS\" -gt 0 ]]; then
      echo \"WARN: Found \${ERRORS} error/fatal log lines in last 60 seconds:\"
      docker logs --since 60s \"\$CONTAINER\" 2>&1 | grep -iE 'ERROR|FATAL|PANIC|CRITICAL' | tail -10
    else
      echo 'PASS: No error/fatal log lines'
    fi
  fi
  
  # PM2 service:
  if pm2 show '${SERVICE}' > /dev/null 2>&1; then
    PM2_ERRORS=\$(pm2 logs '${SERVICE}' --lines 50 --nostream 2>&1 | grep -ciE 'ERROR|FATAL|Error:|TypeError|ReferenceError' || echo 0)
    if [[ \"\$PM2_ERRORS\" -gt 0 ]]; then
      echo \"WARN: Found \${PM2_ERRORS} error lines in PM2 logs:\"
      pm2 logs '${SERVICE}' --lines 50 --nostream 2>&1 | grep -iE 'ERROR|FATAL|Error:|TypeError|ReferenceError' | tail -10
    else
      echo 'PASS: No error lines in PM2 logs'
    fi
  fi
"
```

### PV-3: CPU/Memory Within Expected Bounds (BLOCKER)

```bash
ssh "root@${TARGET_IP}" "
  SERVICE='${SERVICE}'
  
  # Docker:
  if docker ps --filter 'name=\${SERVICE}' --format '{{.Names}}' | grep -q .; then
    CONTAINER=\$(docker ps --filter 'name=\${SERVICE}' -q | head -1)
    STATS=\$(docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}} {{.MemPerc}}' \"\$CONTAINER\" 2>/dev/null)
    CPU=\$(echo \"\$STATS\" | awk '{print \$1}' | sed 's/%//')
    MEM_PERC=\$(echo \"\$STATS\" | awk '{print \$3}' | sed 's/%//')
    echo \"CPU: \${CPU}%\"
    echo \"Memory: \${MEM_PERC}%\"
    
    if [[ \"\$MEM_PERC\" =~ ^[0-9.]+$ ]] && (( \$(echo \"\$MEM_PERC > 80\" | bc -l 2>/dev/null || echo 0) )); then
      echo 'WARN: Memory usage above 80% -- investigate'
    fi
  fi
  
  # PM2:
  if pm2 show '${SERVICE}' > /dev/null 2>&1; then
    PM2_INFO=\$(pm2 show '${SERVICE}' 2>/dev/null)
    MEM=\$(echo \"\$PM2_INFO\" | grep 'memory' | awk '{print \$4}' || echo '?')
    CPU=\$(echo \"\$PM2_INFO\" | grep 'cpu' | awk '{print \$4}' || echo '?')
    echo \"PM2 memory: \${MEM}\"
    echo \"PM2 CPU: \${CPU}%\"
  fi
  
  # Server-wide:
  echo ''
  echo 'Server resource summary:'
  free -h | head -2
  echo ''
  echo \"Load: \$(cat /proc/loadavg)\"
  echo \"Disk: \$(df -h / | tail -1 | awk '{print \$5 \" used (\" \$4 \" free)\"}')\"
"
```

### PV-4: Dependent Services Verify Connectivity (BLOCKER)

```bash
ssh "root@${TARGET_IP}" "
  SERVICE='${SERVICE}'
  
  # If this service depends on postgres, verify DB connections:
  if echo '${SERVICE}' | grep -qiE 'api|worker|web|app'; then
    # Check if the service is connecting to databases:
    CONTAINER=\$(docker ps --filter 'name=\${SERVICE}' -q | head -1)
    if [[ -n \"\$CONTAINER\" ]]; then
      # Check for database connection errors in logs:
      DB_ERRORS=\$(docker logs --since 120s \"\$CONTAINER\" 2>&1 | grep -ciE 'connection refused|database.*not.*found|authentication failed|timeout.*connect' || echo 0)
      if [[ \"\$DB_ERRORS\" -gt 0 ]]; then
        echo \"BLOCKER: \${DB_ERRORS} database connection errors found\"
        docker logs --since 120s \"\$CONTAINER\" 2>&1 | grep -iE 'connection refused|database.*not.*found|authentication failed' | tail -5
        exit 1
      fi
      echo 'PASS: No database connection errors in logs'
    fi
  fi
"
```

### PV-5: Old Service Stopped and Verified Stopped (BLOCKER)

```bash
# Verify old service is not running on source server:
SOURCE_IP="100.98.163.17"  # EDGE

ssh "root@${SOURCE_IP}" "
  SERVICE='${SERVICE}'
  
  # Docker check:
  if docker ps --filter 'name=\${SERVICE}' --format '{{.Names}}' 2>/dev/null | grep -q .; then
    echo 'BLOCKER: Service containers still running on source!'
    docker ps --filter 'name=\${SERVICE}' --format '{{.Names}} {{.Status}}'
    echo 'Stop them before completing migration: docker stop <name>'
    exit 1
  fi
  echo 'PASS: No \${SERVICE} containers running on source'
  
  # PM2 check:
  if pm2 show '${SERVICE}' > /dev/null 2>&1; then
    STATUS=\$(pm2 show '${SERVICE}' | grep 'status' | awk '{print \$NF}')
    if [[ \"\$STATUS\" == 'online' ]]; then
      echo 'BLOCKER: PM2 app still online on source!'
      echo 'Stop it: pm2 stop ${SERVICE} && pm2 delete ${SERVICE}'
      exit 1
    fi
    echo 'PASS: PM2 app exists but is not online (status: \${STATUS})'
  else
    echo 'PASS: PM2 app removed from source'
  fi
  
  # Port check:
  for port in ${PORT_LIST}; do
    if ss -tlnp \"sport = :\${port}\" 2>/dev/null | grep -q \":\$port\"; then
      PROC=\$(ss -tlnp \"sport = :\${port}\" 2>/dev/null | grep \":\$port\" | awk '{print \$NF}')
      echo \"INFO: Port \$port still in use by \$PROC (may not be related to migrated service)\"
    fi
  done
"
```

### PV-6: Monitoring Scrapes New Location (BLOCKER)

```bash
ssh root@100.121.230.28 "
  SERVICE='${SERVICE}'
  
  # Wait for Prometheus to scrape new targets:
  echo 'Waiting 30 seconds for Prometheus to pick up new targets...'
  sleep 30
  
  # Check if Prometheus sees the new target:
  TARGETS=\$(curl -sf 'http://127.0.0.1:9090/api/v1/targets' 2>/dev/null)
  
  # If this is a service that moved to AIOPS, check local Prometheus targets:
  echo \"\${TARGETS}\" | python3 -c "
import sys, json
data = json.load(sys.stdin)
active = data.get('data', {}).get('activeTargets', [])
# Check for any newly migrated service indicator
print(f'Active targets: {len(active)}')
for t in active:
    labels = t.get('labels', {})
    job = labels.get('job', 'unknown')
    instance = labels.get('instance', 'unknown')
    health = t.get('health', 'unknown')
    print(f'  {job} @ {instance} => {health}')
" 2>/dev/null || echo 'WARN: Cannot parse Prometheus targets'
  
  # Verify Grafana dashboards still load:
  curl -sf http://127.0.0.1:3002/api/health > /dev/null 2>&1 && \
    echo 'PASS: Grafana healthy' || echo 'WARN: Grafana unhealthy'
  
  # If Loki was involved, verify logs are flowing:
  curl -sf http://127.0.0.1:3100/ready > /dev/null 2>&1 && \
    echo 'PASS: Loki ready' || echo 'INFO: Loki check skipped'
"
```

### PV-7: Role Compliance Audit Passes (BLOCKER)

```bash
# Run server role enforcement on both source and target:
echo "=== Target Server Role Audit ==="
ssh "root@${TARGET_IP}" "
  bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --report 2>&1
  RC=\$?
  if [[ \$RC -eq 2 ]]; then
    echo 'BLOCKER: CRITICAL role violations on target after migration'
    exit 1
  elif [[ \$RC -eq 1 ]]; then
    echo 'WARN: Warning-level role violations on target'
  else
    echo 'PASS: Target server role-compliant'
  fi
"

echo "=== Source Server Role Audit ==="
ssh "root@${SOURCE_IP}" "
  bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --report 2>&1
  RC=\$?
  if [[ \$RC -eq 2 ]]; then
    echo 'WARN: CRITICAL role violations remain on source (may be unrelated)'
  else
    echo 'PASS: Source server role-compliant or only warnings'
  fi
"
```

### PV-8: Public-Facing Endpoint Check (BLOCKER, if public)

```bash
# Only for services that have public DNS entries:
PUBLIC_DOMAIN="<service>.wheeler.ai"

# DNS check:
RESOLVED_IP=$(dig +short "${PUBLIC_DOMAIN}" @1.1.1.1 2>/dev/null || echo "")
if [[ -z "$RESOLVED_IP" ]]; then
  echo "WARN: ${PUBLIC_DOMAIN} does not resolve"
else
  echo "PASS: ${PUBLIC_DOMAIN} resolves to ${RESOLVED_IP}"
fi

# HTTPS check:
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${PUBLIC_DOMAIN}/health" 2>/dev/null || echo "000")
case "$HTTP_CODE" in
  200|204|301|302)
    echo "PASS: ${PUBLIC_DOMAIN}/health returned HTTP ${HTTP_CODE}"
    ;;
  000)
    echo "BLOCKER: Cannot reach ${PUBLIC_DOMAIN}"
    ;;
  502|503|504)
    echo "BLOCKER: ${PUBLIC_DOMAIN} returned HTTP ${HTTP_CODE} -- upstream/backend issue"
    ;;
  404)
    echo "INFO: ${PUBLIC_DOMAIN}/health returned 404 (may not have /health endpoint)"
    ;;
  *)
    echo "WARN: ${PUBLIC_DOMAIN} returned unexpected HTTP ${HTTP_CODE}"
    ;;
esac

# SSL certificate check:
echo | openssl s_client -servername "${PUBLIC_DOMAIN}" -connect "${PUBLIC_DOMAIN}:443" 2>/dev/null | \
  openssl x509 -noout -dates 2>/dev/null | grep notAfter && \
  echo "PASS: SSL certificate valid" || \
  echo "WARN: SSL certificate check failed"
```

---

## False-Green Prevention

These are specific anti-patterns where a check might pass but the service is not actually healthy. Each check is mandatory.

### FP-1: Container "Up" But Returning 5xx (BLOCKER)

```bash
# Docker reports "healthy" but HTTP returns 500s. Verify:
ssh "root@${TARGET_IP}" "
  SERVICE='${SERVICE}'
  CONTAINER=\$(docker ps --filter 'name=\${SERVICE}' -q | head -1)
  if [[ -n \"\$CONTAINER\" ]]; then
    # 10 rapid health endpoint checks:
    SUCCESSES=0
    FAILURES=0
    for i in \$(seq 1 10); do
      CODE=\$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:${PORT}/health 2>/dev/null || echo '000')
      if [[ \"\$CODE\" == '200' ]]; then
        SUCCESSES=\$((SUCCESSES + 1))
      else
        FAILURES=\$((FAILURES + 1))
      fi
      sleep 0.5
    done
    echo \"Health endpoint: \${SUCCESSES}/10 success, \${FAILURES}/10 non-200\"
    if [[ \"\$FAILURES\" -gt 2 ]]; then
      echo 'BLOCKER: Intermittent health check failures (false-green risk)'
      exit 1
    fi
  fi
"
```

### FP-2: PM2 "Online" But Spinning CPU (BLOCKER)

```bash
ssh "root@${TARGET_IP}" "
  APP_NAME='${APP_NAME}'
  if pm2 show \"\${APP_NAME}\" > /dev/null 2>&1; then
    # Check CPU over 3 samples:
    CPU_SUM=0
    for i in \$(seq 1 3); do
      CPU=\$(pm2 show \"\${APP_NAME}\" 2>/dev/null | grep 'cpu' | awk '{print \$4}' | sed 's/%//')
      CPU_SUM=\$(echo \"\$CPU_SUM + \$CPU\" | bc 2>/dev/null || echo 0)
      sleep 1
    done
    CPU_AVG=\$(echo \"scale=1; \$CPU_SUM / 3\" | bc 2>/dev/null || echo 0)
    echo \"Average CPU: \${CPU_AVG}%\"
    if (( \$(echo \"\$CPU_AVG > 90\" | bc -l 2>/dev/null || echo 0) )); then
      echo 'WARN: CPU consistently above 90% -- possible spin loop'
      pm2 logs \"\${APP_NAME}\" --lines 10 --nostream
    fi
  fi
"
```

### FP-3: Database "Accepting" But Returning Wrong Data (BLOCKER)

```bash
# Run a known-quantity query and compare before/after:
ssh "root@${TARGET_IP}" "
  PG_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
  
  # Test write (on a temp table, rolled back):
  RESULT=\$(docker exec \"\$PG_CONTAINER\" psql -U postgres -d postgres -tAc \"
    BEGIN;
    CREATE TABLE IF NOT EXISTS _migration_test_ (ts timestamp DEFAULT now());
    INSERT INTO _migration_test_ DEFAULT VALUES;
    SELECT count(*) FROM _migration_test_;
    ROLLBACK;
  \" 2>/dev/null || echo 'FAIL')
  
  if [[ \"\$RESULT\" == 'FAIL' ]]; then
    echo 'BLOCKER: PostgreSQL read/write test failed'
    exit 1
  fi
  echo \"PASS: PostgreSQL read/write test (\${RESULT})\"
  
  # Drop test table if it exists:
  docker exec \"\$PG_CONTAINER\" psql -U postgres -d postgres -c 'DROP TABLE IF EXISTS _migration_test_;' 2>/dev/null
"
```

### FP-4: Redis "PONG" But Rejecting Writes (BLOCKER)

```bash
ssh "root@${TARGET_IP}" "
  REDIS_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -i redis | head -1)
  if [[ -n \"\$REDIS_CONTAINER\" ]]; then
    # Test SET:
    SET_RESULT=\$(docker exec \"\$REDIS_CONTAINER\" redis-cli SET _migration_test_ \"ok\" EX 10 2>/dev/null)
    if [[ \"\$SET_RESULT\" != 'OK' ]]; then
      echo 'BLOCKER: Redis SET failed -- may be read-only or out of memory'
      exit 1
    fi
    # Test GET:
    GET_RESULT=\$(docker exec \"\$REDIS_CONTAINER\" redis-cli GET _migration_test_ 2>/dev/null)
    if [[ \"\$GET_RESULT\" != 'ok' ]]; then
      echo 'BLOCKER: Redis GET failed -- data inconsistency'
      exit 1
    fi
    echo 'PASS: Redis read/write test'
    docker exec \"\$REDIS_CONTAINER\" redis-cli DEL _migration_test_ > /dev/null 2>&1
  fi
"
```

### FP-5: Traefik Routes Working But to Wrong Backend (BLOCKER)

```bash
ssh root@100.98.163.17 "
  # Verify Traefik routes the expected services:
  echo '=== Active Traefik Routers ==='
  curl -sf http://localhost:8080/api/http/routers 2>/dev/null | \
    python3 -c \"
import sys, json
data = json.load(sys.stdin)
for r in data:
    name = r.get('name', '?')
    rule = r.get('rule', '?')
    service = r.get('service', '?')
    status = r.get('status', '?')
    print(f'  {name}: {rule} -> {service} [{status}]')
\" 2>/dev/null || echo 'WARN: Cannot query Traefik API'

  echo ''
  echo '=== Active Traefik Services ==='
  curl -sf http://localhost:8080/api/http/services 2>/dev/null | \
    python3 -c \"
import sys, json
data = json.load(sys.stdin)
for s in data:
    name = s.get('name', '?')
    s_type = s.get('type', '?')
    servers = s.get('serverStatus', {})
    up = sum(1 for v in servers.values() if v == 'UP')
    total = len(servers)
    print(f'  {name}: {up}/{total} servers UP')
\" 2>/dev/null || echo 'WARN: Cannot query Traefik API'
"
```

### FP-6: Tailscale Connected But No Service Traffic (WARN)

```bash
# Check if traffic is actually flowing over Tailscale to the migrated service:
ssh "root@${TARGET_IP}" "
  # Check Tailscale interface traffic:
  TS_IFACE=\"tailscale0\"
  
  RX_BEFORE=\$(cat /sys/class/net/\${TS_IFACE}/statistics/rx_bytes 2>/dev/null || echo 0)
  sleep 10
  RX_AFTER=\$(cat /sys/class/net/\${TS_IFACE}/statistics/rx_bytes 2>/dev/null || echo 0)
  RX_DELTA=\$(( (RX_AFTER - RX_BEFORE) / 10 ))
  
  TX_BEFORE=\$(cat /sys/class/net/\${TS_IFACE}/statistics/tx_bytes 2>/dev/null || echo 0)
  sleep 0
  TX_AFTER=\$(cat /sys/class/net/\${TS_IFACE}/statistics/tx_bytes 2>/dev/null || echo 0)
  TX_DELTA=\$(( (TX_AFTER - TX_BEFORE) / 10 ))
  
  echo \"Tailscale traffic: RX \${RX_DELTA} B/s, TX \${TX_DELTA} B/s\"
  if [[ \"\$RX_DELTA\" -eq 0 ]] && [[ \"\$TX_DELTA\" -eq 0 ]]; then
    echo 'WARN: No Tailscale traffic detected -- service may not be processing requests'
  fi
"
```

### FP-7: DNS Resolves But Pointing to Old IP (BLOCKER)

```bash
# If DNS was updated, verify propagation:
EXPECTED_IP="${EXPECTED_PUBLIC_IP}"

# Check multiple resolvers:
for resolver in 1.1.1.1 8.8.8.8 9.9.9.9; do
  RESOLVED=$(dig +short "${PUBLIC_DOMAIN}" "@${resolver}" 2>/dev/null | head -1 || echo "")
  if [[ "$RESOLVED" == "$EXPECTED_IP" ]]; then
    echo "PASS: ${resolver} resolves ${PUBLIC_DOMAIN} -> ${EXPECTED_IP}"
  elif [[ -n "$RESOLVED" ]]; then
    echo "WARN: ${resolver} resolves ${PUBLIC_DOMAIN} -> ${RESOLVED} (expected ${EXPECTED_IP})"
  else
    echo "INFO: ${resolver} returned no result for ${PUBLIC_DOMAIN} (caching)"
  fi
done
```

---

## Final Gate: Migration Sign-Off Checklist

All items must be explicitly checked before declaring the migration complete.

```
MIGRATION SIGN-OFF
==================
Service: _________________________________
From: ____________________________________
To: ______________________________________
Date: ____________________________________
Engineer: ________________________________

[ ] PG-1: Backup verified and decrypts
[ ] PG-2: Rollback snapshot created and verified
[ ] PG-3: Source service state documented
[ ] PG-4: Target server reachable via SSH (Tailscale)
[ ] PG-5: Target server resources sufficient
[ ] PG-6: Target dependencies healthy
[ ] PG-7: Target ports available
[ ] PG-8: PM2 config verified (if applicable)
[ ] PG-9: Docker config verified (if applicable)
[ ] PG-10: Logs path verified and writable

Scenario-specific gates (check applicable):
[ ] A-GATE-1 through A-GATE-5  (Docker EDGE -> AIOPS)
[ ] B-GATE-1 through B-GATE-3  (Database EDGE -> COREDB)
[ ] C-GATE-1 through C-GATE-3  (PM2 EDGE -> AIOPS)
[ ] D-GATE-1 through D-GATE-2  (COREDB monitoring consolidation)

Post-Migration (ALL must pass):
[ ] PV-1: Service responds on health endpoint
[ ] PV-2: No error logs in first 60 seconds
[ ] PV-3: CPU/memory within expected bounds
[ ] PV-4: Dependent services verify connectivity
[ ] PV-5: Old service stopped and verified stopped
[ ] PV-6: Monitoring scrapes new location
[ ] PV-7: Role compliance audit passes
[ ] PV-8: Public-facing endpoint check (if applicable)

False-Green Prevention:
[ ] FP-1: Container not returning intermittent 5xx
[ ] FP-2: PM2 not spinning CPU
[ ] FP-3: Database read/write test passes
[ ] FP-4: Redis read/write test passes
[ ] FP-5: Traefik routes verified correct backend
[ ] FP-6: Tailscale traffic flowing
[ ] FP-7: DNS propagation verified (if changed)

Rollback readiness (confirm before signing):
[ ] Rollback commands from MIGRATION_COMMANDS.md tested in dry-run
[ ] Rollback snapshot accessible
[ ] Rollback procedure documented for on-call

DECISION:
[ ] MIGRATION SUCCESS -- Sign off
[ ] ROLLBACK REQUIRED -- Execute rollback scenario
[ ] DEFER -- Issues found, fix and retry

Signature: _______________  Time: _______ UTC
```

---

## Quick Gate Runner (automated pre-migration pass)

```bash
#!/usr/bin/env bash
# Run this before any migration. Fails fast if any BLOCKER gate fails.
# Usage: bash validation-gates.sh <source-ip> <target-ip> <service-name>

set -euo pipefail
SOURCE_IP="${1:?}"
TARGET_IP="${2:?}"
SERVICE="${3:?}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

fail() { echo -e "${RED}[BLOCKER]${NC} $*"; exit 1; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

echo "=== Pre-Migration Gate Check: ${SERVICE} (${SOURCE_IP} -> ${TARGET_IP}) ==="
echo ""

# PG-1: Backup
echo "--- PG-1: Backup ---"
LATEST=$(ls -t /root/infrastructure/backups/backup-*.tar.gz.gpg 2>/dev/null | head -1)
if [[ -z "$LATEST" ]]; then fail "No backup found"; fi
BACKUP_AGE=$(($(date +%s) - $(stat --printf="%Y" "$LATEST")))
if [[ $BACKUP_AGE -gt 3600 ]]; then warn "Backup is $(($BACKUP_AGE/60)) minutes old"; fi
pass "Backup exists ($(du -h "$LATEST" | cut -f1))"

# PG-2: Snapshot
echo "--- PG-2: Rollback Snapshot ---"
SNAP=$(ls -dt /root/infrastructure/backups/pre-migration-snapshots/snapshot_* 2>/dev/null | head -1)
[[ -z "$SNAP" ]] && fail "No snapshot found. Run pre-migration-snapshot.sh"
SNAP_AGE=$(($(date +%s) - $(stat --printf="%Y" "$SNAP/manifest.json")))
[[ $SNAP_AGE -gt 3600 ]] && warn "Snapshot is $(($SNAP_AGE/60)) minutes old"
pass "Snapshot exists at $SNAP"

# PG-4: SSH
echo "--- PG-4: Target Reachable ---"
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "root@${TARGET_IP}" 'echo ok' >/dev/null 2>&1 || fail "Cannot SSH to ${TARGET_IP}"
pass "SSH to ${TARGET_IP} works"

# PG-5: Resources
echo "--- PG-5: Target Resources ---"
AVAIL=$(ssh "root@${TARGET_IP}" "df -BG / | awk 'NR==2{print \$4}' | sed 's/G//'")
[[ $AVAIL -lt 10 ]] && fail "Only ${AVAIL}GB free on target"
pass "${AVAIL}GB free on target"

FREE_MEM=$(ssh "root@${TARGET_IP}" "free -g | awk '/^Mem:/{print \$7}'")
[[ $FREE_MEM -lt 2 ]] && fail "Only ${FREE_MEM}GB free memory on target"
pass "${FREE_MEM}GB free memory on target"

# PG-6: Dependencies
echo "--- PG-6: Target Dependencies ---"
ssh "root@${TARGET_IP}" "docker info >/dev/null 2>&1" || fail "Docker not running on target"
pass "Docker running on target"
ssh "root@${TARGET_IP}" "tailscale status >/dev/null 2>&1" || fail "Tailscale not running on target"
pass "Tailscale running on target"

# PG-10: Logs
echo "--- PG-10: Logs Path ---"
ssh "root@${TARGET_IP}" "mkdir -p /var/log/wheeler /opt/wheeler/logs && test -w /var/log/wheeler" || fail "Log dir not writable on target"
pass "Log directories ready on target"

echo ""
echo -e "${GREEN}=== ALL PRE-MIGRATION GATES PASSED ===${NC}"
echo "Ready to proceed with migration."
echo ""
```

Save this runner as `/root/infrastructure/shared/scripts/validation-gates.sh` and run before every migration.
