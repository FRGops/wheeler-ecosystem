# Wheeler Enterprise — Next 30 Days Action Plan

**Window:** 2026-05-31 → 2026-06-29
**Commander:** SRE Team Lead / Infrastructure Owner
**Depends on:** NEXT_7_DAYS.md Day 7 sign-off (stabilization complete, zero CRITICAL violations)

---

## State Entering This Phase

```
EDGE     Load < 2.0    CPU steal < 25%    (stable, Hostinger-limited)
AIOPS    CPU 40-50%    RAM 18-22GB used   (healthy, room to grow)
COREDB   CPU < 10%     RAM > 4GB used     (databases active, still underutilized)

All CRITICAL violations resolved.
All workers on AIOPS.
All databases on COREDB.
Monitoring unified on AIOPS.
Documentation updated through Day 7.
```

---

## Week 1 (May 31 — Jun 6): Data Architecture Consolidation

**Theme:** Make COREDB the true single source of truth. Eliminate remaining AIOPS-local primary databases.

### Day 8 (May 31): Inventory Remaining Data Sources

```bash
# === Identify all databases that are NOT yet on COREDB ===

# On AIOPS: list all Postgres containers
ssh root@100.64.0.3
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" | grep -iE "postgres|postgis"
# Expected (pre-migration):
#   postgres-aio-main          postgres:16     (AIOPS primary — WRONG, should be on COREDB)
#   prediction-radar-db        postgres:16     (Prediction Radar — WRONG)
#   ravynai-db                 postgres:16     (RavynAI — WRONG)
#   superset-db                postgres:16     (Superset metadata — WRONG)

# On AIOPS: list all Redis instances
docker ps --format "table {{.Names}}\t{{.Image}}" | grep -i redis
# Expected:
#   redis-aio                  redis:7        (AIOPS primary — WRONG if persistence enabled)

# On EDGE: verify zero databases (should be clean after Day 1)
ssh root@100.64.0.2
docker ps --format "table {{.Names}}\t{{.Image}}" | grep -iE "postgres|redis|mongo|mysql|clickhouse"
# EXPECTED: EMPTY
```

### Day 9-10 (Jun 1-2): Migrate Prediction Radar Database to COREDB

```bash
# === Preflight ===
ssh root@100.64.0.4
docker exec postgres-coredb pg_isready -U postgres
# Create target database
docker exec postgres-coredb psql -U postgres -c "CREATE DATABASE prediction_radar OWNER prediction_radar;"

# === Dump from AIOPS ===
ssh root@100.64.0.3
docker exec prediction-radar-db pg_dump -U prediction_radar -d prediction_radar \
  -Fc --no-owner --no-acl -f /tmp/prediction-radar.dump
docker cp prediction-radar-db:/tmp/prediction-radar.dump /tmp/prediction-radar.dump
scp /tmp/prediction-radar.dump root@100.64.0.4:/tmp/

# === Restore to COREDB ===
ssh root@100.64.0.4
docker cp /tmp/prediction-radar.dump postgres-coredb:/tmp/
docker exec postgres-coredb pg_restore -U prediction_radar -d prediction_radar \
  --clean --if-exists --no-owner --no-acl /tmp/prediction-radar.dump

# === Verify row counts match ===
ssh root@100.64.0.3 "docker exec prediction-radar-db psql -U prediction_radar -d prediction_radar -t -c \
  \"SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;\"" > /tmp/pr-source-counts.txt

ssh root@100.64.0.4 "docker exec postgres-coredb psql -U prediction_radar -d prediction_radar -t -c \
  \"SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;\"" > /tmp/pr-target-counts.txt

diff /tmp/pr-source-counts.txt /tmp/pr-target-counts.txt

# === Cutover: Update Prediction Radar connection string ===
ssh root@100.64.0.3
# Edit Docker Compose env for prediction-radar
cd /root/infrastructure/aiops/prediction-radar
# Change DATABASE_URL to point to 100.64.0.4:5432/prediction_radar
docker compose down prediction-radar-api prediction-radar-worker prediction-radar-scheduler
docker compose up -d prediction-radar-api prediction-radar-worker prediction-radar-scheduler

# === Smoke test ===
curl -s https://predictionradar.wheeler.ai/health

# === After 24h stable, remove AIOPS-local prediction-radar-db container ===
ssh root@100.64.0.3
docker stop prediction-radar-db
# Keep volume for 7 days as rollback insurance, then delete
```

### Day 11-12 (Jun 3-4): Migrate RavynAI Database to COREDB

```bash
# Same pattern as Prediction Radar migration above
# Replace prediction_radar with ravynai throughout
# Database user: ravynai
# Database name: ravynai
# Connection string update: /root/infrastructure/aiops/ravynai/.env or docker-compose.yml
```

### Day 13-14 (Jun 5-6): Migrate Superset Metadata DB + Redis Consolidation

```bash
# === Superset metadata (small database, quick migration) ===
ssh root@100.64.0.3
docker exec superset-db pg_dump -U superset -d superset -Fc -f /tmp/superset.dump
docker cp superset-db:/tmp/superset.dump /tmp/
scp /tmp/superset.dump root@100.64.0.4:/tmp/

ssh root@100.64.0.4
docker cp /tmp/superset.dump postgres-coredb:/tmp/
docker exec postgres-coredb psql -U postgres -c "CREATE DATABASE superset OWNER superset;"
docker exec postgres-coredb pg_restore -U superset -d superset --clean --if-exists /tmp/superset.dump

# Update Superset config on AIOPS to use COREDB
ssh root@100.64.0.3
# SUPERSET__SQLALCHEMY_DATABASE_URI=postgresql://superset@100.64.0.4:5432/superset
docker restart superset

# === Redis consolidation ===
# At this point, the only Redis that should persist is on COREDB.
# AIOPS Redis instances should be cache-only with allkeys-lru eviction.

ssh root@100.64.0.3
# Check Redis persistence config
for redis_container in $(docker ps --filter "name=redis" -q); do
  name=$(docker inspect --format '{{.Name}}' "$redis_container" | sed 's/\///')
  appendonly=$(docker exec "$redis_container" redis-cli CONFIG GET appendonly 2>/dev/null | tail -1)
  save=$(docker exec "$redis_container" redis-cli CONFIG GET save 2>/dev/null | tail -1)
  eviction=$(docker exec "$redis_container" redis-cli CONFIG GET maxmemory-policy 2>/dev/null | tail -1)
  echo "$name: appendonly=$appendonly save=$save eviction=$eviction"
done

# For any AIOPS Redis with persistence: disable it (data is on COREDB)
# docker exec redis-aio redis-cli CONFIG SET appendonly no
# docker exec redis-aio redis-cli CONFIG SET save ""
# docker exec redis-aio redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

**Week 1 Success Criteria:**
- [ ] ALL application databases running on COREDB (single Postgres instance with multiple databases)
- [ ] Zero primary (write-master) databases on AIOPS
- [ ] AIOPS-local Redis instances are cache-only (no persistence)
- [ ] COREDB Postgres has 4+ databases: frgops, prediction_radar, ravynai, superset
- [ ] `enforce-roles.sh --server aiops --report` shows zero CRITICAL database violations

---

## Week 2 (Jun 7-13): Monitoring, Alerting, and Observability Maturity

**Theme:** From "it works" to "we trust it." Complete monitoring coverage, tested alerting, logging completeness.

### Day 15 (Jun 7): Prometheus Recording Rules and Dashboards

```bash
# === Add recording rules for key business metrics ===
ssh root@100.64.0.3

cat >> /etc/prometheus/rules/recording.yml << 'RULESEOF'
groups:
  - name: wheeler_business
    interval: 30s
    rules:
      - record: job:queue_depth:avg5m
        expr: avg_over_time(bull_queue_waiting[5m])
      - record: job:api_latency:p95_5m
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
      - record: instance:cpu_utilization:avg5m
        expr: avg by(instance) (100 - rate(node_cpu_seconds_total{mode="idle"}[5m]) * 100)
      - record: instance:memory_usage:pct
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100
  - name: wheeler_sla
    interval: 1m
    rules:
      - record: probe:http_status:rate5m
        expr: rate(probe_http_status_code[5m])
      - record: slo:availability:30d
        expr: avg_over_time(probe_success[30d]) * 100
RULESEOF

docker restart prometheus
# Verify rules loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | .name'
```

### Day 16 (Jun 8): Grafana Dashboard Standardization

```bash
# === Create/verify the minimum dashboard set ===

# Dashboard 1: Server Overview
#   - CPU, RAM, Disk for all 3 servers (3 rows x 3 panels each)
#   - Load average timeseries
#   - Network IO

# Dashboard 2: Database Health
#   - Connections per database
#   - Query latency p50/p95/p99
#   - Cache hit ratio
#   - Replication lag (if replicas enabled)
#   - Dead tuples / bloat ratio

# Dashboard 3: Application Health
#   - Request rate by endpoint
#   - Error rate (4xx/5xx) by service
#   - P95 latency per endpoint
#   - Queue depth (BullMQ)

# Dashboard 4: EDGE-Specific
#   - CPU steal timeseries (MOST IMPORTANT for Hostinger)
#   - Traefik request rate / error rate
#   - SSL cert expiry countdown
#   - Bandwidth usage

# Provisioning: commit dashboards as JSON to infrastructure repo
# Path: /root/infrastructure/enterprise/phase2-observability/dashboards/

# Verify all 4 dashboards load:
for dash in "server-overview" "database-health" "application-health" "edge-metrics"; do
  exists=$(curl -s -H "Authorization: Bearer $GRAFANA_API_KEY" \
    "http://localhost:3002/api/search?query=$dash" | jq '. | length')
  echo "$dash: $exists dashboard(s) found"
done
```

### Day 17 (Jun 9): Alerting Rules — Production-Grade

```bash
# === Define alerting rules with real thresholds ===
ssh root@100.64.0.3

cat > /etc/prometheus/rules/alerts.yml << 'ALERTSEOF'
groups:
  - name: server_health
    rules:
      - alert: HostHighCpuSteal
        expr: avg by(instance)(rate(node_cpu_seconds_total{mode="steal"}[5m]) * 100) > 30
        for: 10m
        labels: {severity: warning}
        annotations:
          summary: "EDGE CPU steal > 30% (Hostinger host overcommitted)"
          description: "{{ $labels.instance }} steal is {{ $value }}%. If > 40% for 30m, consider migration."
          runbook_url: "https://wiki.wheeler.ai/runbooks/host-high-cpu-steal"

      - alert: HostHighLoad
        expr: node_load1 / count without(cpu)(node_cpu_seconds_total{mode="idle"}) > 1.5
        for: 15m
        labels: {severity: warning}
        annotations:
          summary: "Server load > 1.5x CPU count"
          runbook_url: "https://wiki.wheeler.ai/runbooks/host-high-load"

      - alert: HostOutOfMemory
        expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10
        for: 5m
        labels: {severity: critical}
        annotations:
          summary: "Server has < 10% memory available"
          runbook_url: "https://wiki.wheeler.ai/runbooks/host-out-of-memory"

      - alert: HostDiskWillFillIn24h
        expr: predict_linear(node_filesystem_free_bytes{mountpoint="/"}[1h], 86400) < 0
        for: 1h
        labels: {severity: warning}
        annotations:
          summary: "Disk will fill in < 24 hours at current rate"

      - alert: HostSwapUsage
        expr: node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes > 100 * 1024 * 1024
        for: 15m
        labels: {severity: warning}
        annotations:
          summary: "Swap usage > 100MB on {{ $labels.instance }}"

  - name: service_health
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 2m
        labels: {severity: page}
        annotations:
          summary: "{{ $labels.job }} on {{ $labels.instance }} is DOWN"
          runbook_url: "https://wiki.wheeler.ai/runbooks/service-down"

      - alert: PostgresDown
        expr: pg_up == 0
        for: 1m
        labels: {severity: critical}
        annotations:
          summary: "PostgreSQL is not responding"
          runbook_url: "https://wiki.wheeler.ai/runbooks/postgres-down"

      - alert: PostgresTooManyConnections
        expr: pg_stat_database_numbackends / pg_settings_max_connections > 0.85
        for: 5m
        labels: {severity: warning}

  - name: application_health
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
        for: 5m
        labels: {severity: warning}
        annotations:
          summary: "5xx error rate > 5% for {{ $labels.service }}"

      - alert: HighLatency
        expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 2
        for: 5m
        labels: {severity: warning}
        annotations:
          summary: "P99 latency > 2s for {{ $labels.service }}"

  - name: role_compliance
    rules:
      - alert: CriticalRoleViolation
        expr: wheeler_role_violations{severity="critical"} > 0
        for: 5m
        labels: {severity: page}
        annotations:
          summary: "CRITICAL role violation on {{ $labels.server }}"
          description: "Container {{ $labels.container }} is on the wrong server"
          runbook_url: "https://wiki.wheeler.ai/runbooks/role-violation"

      - alert: UnlabeledContainer
        expr: wheeler_containers_unlabeled > 0
        for: 1h
        labels: {severity: warning}
        annotations:
          summary: "Unlabeled containers detected on {{ $labels.server }}"
ALERTSEOF

# Reload Prometheus
curl -X POST http://localhost:9090/-/reload

# Verify alerts loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name | startswith("service") or startswith("server") or startswith("application") or startswith("role")) | {name: .name, rules: [.rules[] | .name]}'
```

### Day 18-19 (Jun 10-11): Alertmanager Routing — Slack and PagerDuty

```bash
ssh root@100.64.0.3

cat > /etc/alertmanager/alertmanager.yml << 'AMEOF'
global:
  slack_api_url: '${SLACK_WEBHOOK_URL}'  # from env or vault

route:
  receiver: 'slack-default'
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 2m
  repeat_interval: 4h

  routes:
    - match:
        severity: page
      receiver: 'pagerduty-critical'
      continue: true
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
      continue: true
    - match:
        severity: warning
      receiver: 'slack-engineering'
    - match:
        alertname: CriticalRoleViolation
      receiver: 'pagerduty-critical'

receivers:
  - name: 'slack-default'
    slack_configs:
      - channel: '#alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: >-
          {{ range .Alerts }}
          *Alert:* {{ .Annotations.summary }}
          *Severity:* {{ .Labels.severity }}
          *Instance:* {{ .Labels.instance }}
          *Description:* {{ .Annotations.description }}
          {{ end }}

  - name: 'slack-engineering'
    slack_configs:
      - channel: '#engineering'

  - name: 'pagerduty-critical'
    pagerduty_configs:
      - routing_key: '${PAGERDUTY_ROUTING_KEY}'
        severity: '{{ if eq .Labels.severity "page" }}critical{{ else }}error{{ end }}'
        description: '{{ .CommonAnnotations.summary }}'

inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: ['instance']
AMEOF

docker restart alertmanager

# Verify config loaded
curl -s http://localhost:9093/api/v2/status | jq '.config.original | fromyaml | .route.receiver'
# EXPECTED: "slack-default"
```

### Day 20-21 (Jun 12-13): Logging Completeness

```bash
# === Verify promtail is shipping logs from ALL services ===

# 1. Check promtail on each server
for server in edge aiops coredb; do
  case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
  echo "=== $server ==="
  ssh root@100.64.0.$ip "
    docker ps --filter 'name=promtail' --format '{{.Status}}'
    docker exec promtail cat /etc/promtail/config.yml 2>/dev/null | grep -A10 'scrape_configs'
  " 2>/dev/null
done

# 2. Query Loki for logs from each server
for server in edge aiops coredb; do
  echo "=== $server last 5 log lines ==="
  curl -s "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode "query={host=\"$server\"}" \
    --data-urlencode "limit=5" \
    --data-urlencode "start=$(date -d '1 hour ago' +%s)000000000" \
    --data-urlencode "end=$(date +%s)000000000" | \
    jq -r '.data.result[0].values[][1]' 2>/dev/null | head -5
done
# EXPECTED: non-empty results for all 3 servers

# 3. Verify log rotation is working
ssh root@100.64.0.3
docker inspect $(docker ps -q) --format '{{.Name}} {{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}' | \
  column -t | sort
# EXPECTED: all containers using json-file with max-size=10m max-file=3
# (or loki driver pushing directly)

# 4. Set up Grafana Loki datasource
curl -X POST http://localhost:3002/api/datasources \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GRAFANA_API_KEY" \
  -d '{
    "name": "Loki",
    "type": "loki",
    "url": "http://loki:3100",
    "access": "proxy",
    "isDefault": false
  }'
```

**Week 2 Success Criteria:**
- [ ] Prometheus recording rules producing business metrics (queue depth, API latency, SLA)
- [ ] 4 standard Grafana dashboards loading with data
- [ ] 12+ alerting rules defined with runbook_url annotations
- [ ] Alertmanager routing to Slack (verified with test alert)
- [ ] PagerDuty integration configured (test page sent and acknowledged)
- [ ] Loki receiving logs from all 3 servers (verified with query)
- [ ] Log rotation correctly configured on all containers

---

## Week 3 (Jun 14-20): Security Hardening and Compliance

**Theme:** Lock down every server to its role. Pass compliance audit with zero findings.

### Day 22 (Jun 14): UFW Harden — Close All Gaps

```bash
# === Verify and harden UFW on all servers ===

# EDGE:
ssh root@100.64.0.2
ufw status verbose
# SHOULD be:
#   Status: active
#   Default: deny (incoming), allow (outgoing)
#   22/tcp       ALLOW IN    Anywhere
#   80/tcp       ALLOW IN    Anywhere
#   443/tcp      ALLOW IN    Anywhere
#   Any port on tailscale0  ALLOW IN    100.64.0.0/10

# Verify no unexpected ports open:
ufw status numbered | grep -vE "22|80|443|tailscale|100.64"
# EXPECTED: Empty (no other allow rules)

# AIOPS:
ssh root@100.64.0.3
ufw status verbose
# SHOULD be:
#   Default: deny (incoming), allow (outgoing)
#   Only tailscale0 interface allows incoming
#   NO ports open on 0.0.0.0

# Verify no 0.0.0.0 bindings at all:
ss -tlnp | grep "0.0.0.0" | grep -v "127.0.0"
# EXPECTED: Empty or only localhost services

# COREDB:
ssh root@100.64.0.4
ufw status verbose
# SHOULD be:
#   Default: deny (incoming), deny (outgoing)  # MOST RESTRICTIVE
#   Allow tailscale0:100.64.0.0/10 to specific DB ports
#   Allow outbound: 443 (Tailscale coordination), 53 (DNS)
```

### Day 23 (Jun 15): Tailscale ACL Audit

```bash
# === Review and tighten Tailscale ACLs ===

# 1. Export current ACLs from Tailscale admin console
# 2. Verify these exact rules are in place:

# {
#   "acls": [
#     {"action": "accept", "src": ["tag:edge"],    "dst": ["tag:aiops:80,443,3000-3999,8000-8999"], "proto": "tcp"},
#     {"action": "accept", "src": ["tag:aiops"],   "dst": ["tag:coredb:5432,6379,6432,9000,6333,8123"], "proto": "tcp"},
#     {"action": "accept", "src": ["tag:coredb"],  "dst": ["tag:aiops:3100,9090"], "proto": "tcp"}
#   ]
# }

# 3. Verify EDGE cannot reach COREDB directly:
ssh root@100.64.0.2 "curl -s --connect-timeout 3 http://100.64.0.4:5432" 2>&1
# EXPECTED: Connection refused or timeout (NOT "psql: could not connect")

# 4. Verify COREDB cannot initiate connections to EDGE:
ssh root@100.64.0.4 "curl -s --connect-timeout 3 http://100.64.0.2:80" 2>&1
# EXPECTED: Connection refused or timeout

# 5. Tag all servers correctly in Tailscale admin:
#   EDGE:    tag:edge
#   AIOPS:   tag:aiops
#   COREDB:  tag:coredb
```

### Day 24 (Jun 16): Credential Rotation

```bash
# === Rotate ALL service credentials (post-compromise best practice) ===

# Checklist — each item requires creating new credential, updating .env files,
# restarting affected services, deleting old credential:

# [ ] SSH keys — generate new ED25519 key pair per server
#     ssh-keygen -t ed25519 -f ~/.ssh/wheeler_edge_$(date +%Y%m%d) -C "wheeler-edge"
#     (deploy to all servers, update authorized_keys)

# [ ] Tailscale auth keys — revoke all in admin console, re-issue ephemeral keys

# [ ] Database passwords (postgres, frgops, prediction_radar, ravynai, superset)
#     For each:
#       ssh root@100.64.0.4
#       docker exec postgres-coredb psql -U postgres -c "ALTER USER <user> PASSWORD '<new_strong_password>';"
#       # Update all .env files and docker-compose.yml files that reference this password
#       # Restart affected services
#       # Verify connectivity

# [ ] Redis password (FRGpassword1! MUST be replaced)
#     ssh root@100.64.0.4
#     docker exec redis-coredb redis-cli CONFIG SET requirepass "<new_password>"
#     docker exec redis-coredb redis-cli CONFIG REWRITE
#     # Update all .env files, restart services, verify

# [ ] LiteLLM master key
# [ ] OpenAI API key
# [ ] Anthropic/Claude API key
# [ ] DeepSeek API key (shared by frgcrm-api, surplusai-scraper, voice-agent — rotate once)
# [ ] SendGrid API key
# [ ] Cloudflare API token
# [ ] Grafana admin password
# [ ] MinIO root credentials

# Total: approximately 15 credentials to rotate
# Schedule: 1 hour for databases, 1 hour for API keys, 30 min for SSH/Tailscale
```

### Day 25-26 (Jun 17-18): Container Labeling — 100% Coverage

```bash
# === Ensure EVERY container has com.wheeler.role label ===

# Run audit:
for server in edge aiops coredb; do
  case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
  echo "=== $server ==="
  ssh root@100.64.0.$ip "
    docker ps --format '{{.Names}}' | while read c; do
      role=\$(docker inspect \"\$c\" --format '{{index .Config.Labels \"com.wheeler.role\"}}' 2>/dev/null)
      if [ -z \"\$role\" ]; then
        echo \"  UNLABELED: \$c\"
      fi
    done
  "
done
# EXPECTED: Empty (no unlabeled containers)

# For any unlabeled containers, add labels:
# docker update \
#   --label "com.wheeler.role=<edge|aiops|coredb>" \
#   --label "com.wheeler.service=<service-name>" \
#   --label "com.wheeler.tier=<frontend|backend|data>" \
#   --label "com.wheeler.managed-by=docker-compose" \
#   <container-name>

# Also update the docker-compose.yml for each service to include labels so
# future recreates retain labels.
```

### Day 27 (Jun 19): fail2ban Configuration Audit

```bash
# === Verify fail2ban jails on all servers ===

for server in edge aiops coredb; do
  case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
  echo "=== $server ==="
  ssh root@100.64.0.$ip "
    fail2ban-client status 2>/dev/null | grep 'Jail list'
    for jail in sshd traefik-auth recidive; do
      status=\$(fail2ban-client status \$jail 2>/dev/null | grep -E 'Currently banned|Status')
      [ -n \"\$status\" ] && echo \"  \$jail: \$status\"
    done
  " 2>/dev/null
done
# EXPECTED:
#   All 3 servers: sshd jail active, > 0 banned IPs (normal for public-facing)
#   EDGE: traefik-auth jail active (protecting Traefik auth endpoints)
#   All 3: recidive jail active (repeat offenders get longer bans)
```

### Day 28 (Jun 20): Security Scan and Penetration Test Prep

```bash
# === External scan from your workstation ===

# 1. Port scan EDGE (the only server with public IPs)
nmap -sV -p 1-65535 187.77.148.88 2>/dev/null | grep "open"
# EXPECTED: Only 22 (ssh), 80 (http), 443 (https) open
# If ANY other port is open → IMMEDIATE investigation

# 2. Port scan AIOPS (should see nothing from public)
nmap -sV -p 22,80,443,3000,5432,6379,9090 5.78.140.118 2>/dev/null | grep "open"
# EXPECTED: Empty (UFW should be blocking all)
# If any port open → UFW misconfigured, fix immediately

# 3. Port scan COREDB (should see nothing from public)
nmap -sV -p 22,5432,6379,9000,9100 5.78.210.123 2>/dev/null | grep "open"
# EXPECTED: Empty (UFW should be blocking all)

# 4. SSL certificate check
sslscan wheeler.ai 2>/dev/null | grep -E "Subject|Issuer|Not valid|TLSv1|Heartbleed"
# EXPECTED: TLS 1.3 and 1.2 only, no TLS 1.0/1.1, no Heartbleed

# 5. Check HTTP security headers
curl -sI https://wheeler.ai | grep -iE "strict-transport|x-content-type|x-frame|content-security"
# EXPECTED: HSTS, X-Content-Type-Options, X-Frame-Options, CSP present
```

**Week 3 Success Criteria:**
- [ ] UFW enforcing default-deny on all 3 servers
- [ ] Tailscale ACLs verified — EDGE cannot reach COREDB directly
- [ ] All 15+ credentials rotated
- [ ] Zero unlabeled containers (100% com.wheeler.role coverage)
- [ ] fail2ban active with sshd + recidive jails on all 3 servers
- [ ] External nmap scan shows ONLY ports 22, 80, 443 on EDGE
- [ ] AIOPS and COREDB show ZERO open ports from public internet

---

## Week 4 (Jun 21-27): Reliability and DR Validation

**Theme:** Prove we can recover. Test backups. Exercise DR procedures.

### Day 29 (Jun 21-22): Full Backup Architecture Verification

```bash
# === Verify complete backup pipeline ===

# 1. Verify all database backups running
ssh root@100.64.0.4

# Check crontab for backup jobs
crontab -l | grep -i backup

# Check pgBackRest or pg_dump backup freshness
ls -lt /data/backups/databases/ | head -10
# EXPECTED: most recent backup < 24 hours old

# Check backup sizes (non-zero)
find /data/backups/databases/ -name "*.dump*" -mtime -1 -exec ls -lh {} \;

# 2. Verify WAL archiving (if configured)
ssh root@100.64.0.4
docker exec postgres-coredb psql -U postgres -c \
  "SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());"

ls -lt /data/backups/wal/ | head -5
# EXPECTED: recent WAL files present

# 3. Verify MinIO backup buckets
mc ls coredb-minio/backups/databases/ 2>/dev/null | tail -10

# 4. Verify restic repository integrity
restic -r /data/backups/restic check 2>/dev/null
# EXPECTED: "no errors were found"

# 5. Verify off-site sync (if configured)
# Check rclone/rclone cron job logs
grep -i "sync\|backup" /var/log/syslog | grep -i "rclone\|rsync\|offsite" | tail -10
```

### Day 30 (Jun 23): DR Test — Simulated COREDB Loss

```bash
# === Per DR runbook Section 5: Simulate COREDB total loss ===

# This is a TABLE-TOP exercise (non-disruptive):
# 1. Announce in #engineering: "DR test starting — COREDB loss simulation. No actual service impact."
# 2. Walk through DR runbook Section 5 step by step
# 3. Verify each command works against current infrastructure
# 4. Time each step to validate RTO estimates
# 5. Document discrepancies between runbook and reality

# === Actual partial test: Restore one database to temp instance ===
ssh root@100.64.0.3

# Spin up temp Postgres
docker run -d --name pg-dr-test \
  -e POSTGRES_PASSWORD=test123 \
  -p 15432:5432 \
  postgres:16-alpine
sleep 10
docker exec pg-dr-test pg_isready

# Get latest backup from COREDB
ssh root@100.64.0.4 "ls -t /data/backups/databases/*.dump | head -1" > /tmp/latest-backup-path.txt
scp root@100.64.0.4:$(cat /tmp/latest-backup-path.txt) /tmp/dr-test-backup.dump

# Decrypt if encrypted
# gpg --decrypt /tmp/dr-test-backup.dump.gpg > /tmp/dr-test-backup.dump

# Restore
pg_restore -U postgres -d postgres --clean --if-exists -h localhost -p 15432 \
  /tmp/dr-test-backup.dump

# Verify tables exist
docker exec pg-dr-test psql -U postgres -d postgres -c \
  "SELECT schemaname, count(*) as tables FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') GROUP BY schemaname;"

# Compare row counts with production
# (sample query — adjust per actual database schema)
docker exec pg-dr-test psql -U postgres -d postgres -t -c \
  "SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;" > /tmp/dr-restore-counts.txt

ssh root@100.64.0.4 "docker exec postgres-coredb psql -U postgres -d frgops -t -c \
  \"SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;\"" > /tmp/prod-counts.txt

echo "=== Row count comparison (should be empty = no differences) ==="
diff /tmp/dr-restore-counts.txt /tmp/prod-counts.txt

# Clean up
docker stop pg-dr-test && docker rm pg-dr-test
rm /tmp/dr-test-backup.dump /tmp/dr-restore-counts.txt /tmp/prod-counts.txt

echo "DR test complete. Restore took X seconds (record for RTO tracking)."
```

### Day 31 (Jun 24): DR Test — Simulated AIOPS Loss (Tabletop)

```
Focus on the most impactful scenario (Section 4):
- PM2 apps: 7 on AIOPS — which are critical and in what order to restore?
- Docker services: ~24 containers — dependency order correct in runbook?
- Monitoring gap: Alertmanager is on AIOPS, so if AIOPS is down, NO alerts fire.
  - Mitigation: set up Uptime Kuma on EDGE with independent alerting
```

### Day 32 (Jun 25): Auto-Healing Validation

```bash
# === Verify self-healing mechanisms (phase5) ===

ssh root@100.64.0.3

# 1. Check autoheal container is running
docker ps --filter "name=autoheal" --format "table {{.Names}}\t{{.Status}}"
# EXPECTED: autoheal "Up"

# 2. Check container restart policies
docker ps --format "table {{.Names}}\t{{.Status}}" | awk 'NR>1' | while read name status; do
  policy=$(docker inspect "$name" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
  echo "$name: restart=$policy"
done | grep -v "restart=always\|restart=unless-stopped"
# EXPECTED: Empty (all production containers should have restart=always or unless-stopped)

# 3. Check PM2 auto-respawn
pm2 list | grep -v "online\|stopped\|\-\-\-"
# EXPECTED: No "errored" processes

# 4. Verify Docker daemon auto-restart
systemctl show docker | grep Restart
# EXPECTED: Restart=on-failure, RestartUSec=100ms or similar
```

### Day 33 (Jun 26): Documentation Finalization

```
Update these documents to match current reality:

1. /root/infrastructure/ARCHITECTURE.md
   - Service placement matrix (Hetzner section: remove migrated DBs, add note "now on COREDB")
   - Backup strategy (update: "backups taken FROM COREDB, stored on COREDB MinIO")
   - Monitoring architecture (update: "all three layers on AIOPS")

2. /root/infrastructure/enterprise/phase9-server-roles/server-role-policies.md
   - Add any exceptions granted during this 30-day period
   - Update "NEVER" lists if any policy decisions changed

3. /root/infrastructure/enterprise/phase10-documentation/disaster-recovery.md
   - Update with actual Tailscale IPs confirmed working
   - Fill in emergency contact sheet
   - Add notes from DR tests completed Day 30-31

4. /root/infrastructure/ARCHITECTURE.md (final reconciliation)
   - Run this command to find stale IP references:
     grep -rn "100\.98\.\|100\.121\.\|100\.118\." /root/infrastructure/ --include="*.md" --include="*.sh" --include="*.yml" --include="*.yaml" | grep -v "node_modules" | grep -v ".git"
   - EXPECTED: Empty or only in historical/changelog sections
```

### Day 34 (Jun 27): COREDB Utilization Validation

```bash
# === COREDB is deliberately underutilized — validate this is intentional, not broken ===

ssh root@100.64.0.4

echo "=== COREDB Utilization ==="
echo "CPU: $(top -bn1 | grep 'Cpu' | head -1)"
echo "RAM: $(free -h | awk '/^Mem:/{print $3"/"$2" ("$4" free)"}')"
echo "Disk: $(df -h /data | awk 'NR==2{print $3"/"$2" ("$5" used)"}')"

# List all databases with sizes
docker exec postgres-coredb psql -U postgres -c "
  SELECT datname, pg_size_pretty(pg_database_size(datname)) as size,
         numbackends as connections
  FROM pg_stat_database
  WHERE datname NOT IN ('template0', 'template1')
  ORDER BY pg_database_size(datname) DESC;"

# EXPECTED after migrations:
#   frgops           X GB    N connections  (formerly on EDGE)
#   prediction_radar X GB    N connections  (migrated Week 1)
#   ravynai          X GB    N connections  (migrated Week 1)
#   superset         X MB    N connections  (migrated Week 1)
#   postgres         small   N connections

# Check Redis memory usage
docker exec redis-coredb redis-cli INFO memory | grep -E "used_memory_human|maxmemory_human"
# EXPECTED: used_memory is now meaningful (databases and caches using Redis)

# Check MinIO storage
mc du coredb-minio 2>/dev/null

# If RAM is still < 4GB after all migrations:
# 1. Increase PostgreSQL shared_buffers (e.g., to 2GB if 29GB available)
# 2. Increase effective_cache_size (e.g., to 4GB)
# 3. Or simply accept: COREDB is a vault, not a compute node — low usage is fine
```

**Week 4 Success Criteria:**
- [ ] All backup jobs running, most recent backup < 24h old
- [ ] restic integrity check passes
- [ ] DR test completed: one database restored to temp instance, row counts match production
- [ ] DR tabletop walkthrough completed for AIOPS loss scenario
- [ ] Uptime Kuma has independent alerting channel (not dependent on AIOPS Alertmanager)
- [ ] Auto-healing: autoheal container running, all containers have restart policies
- [ ] Documentation updated and reconciled
- [ ] COREDB utilization validated (RAM > 4GB after all database migrations)
- [ ] FINAL_STABILIZATION_CHECKLIST.md signed off

---

## Days 35-37 (Jun 28-29): Final Sign-off and Continuous Operations Handoff

### Final Compliance Audit

```bash
#!/bin/bash
# /root/infrastructure/enterprise/30-day-final-audit.sh

echo "==============================================="
echo " WHEELER ENTERPRISE — 30-DAY FINAL COMPLIANCE AUDIT"
echo " Date: $(date -u)"
echo "==============================================="
echo ""

FAIL=0

echo "--- Server Health ---"
# EDGE
edge_steal=$(ssh -o ConnectTimeout=5 root@100.64.0.2 "top -bn1 | grep '%Cpu' | grep -oP '[0-9.]+(?= st)'" 2>/dev/null || echo "ERROR")
edge_load=$(ssh -o ConnectTimeout=5 root@100.64.0.2 "cat /proc/loadavg | cut -d' ' -f1" 2>/dev/null || echo "ERROR")
echo "EDGE:  steal=${edge_steal}%  load=${edge_load}  $( [ "$(echo "$edge_steal > 25" | bc -l 2>/dev/null)" = "1" ] && echo 'WARN: steal > 25%' || echo 'OK' )"
echo "EDGE:  $( [ "$(echo "$edge_load > 2.0" | bc -l 2>/dev/null)" = "1" ] && echo 'WARN: load > 2.0' || echo 'load OK' )"

# AIOPS
aiops_cpu=$(ssh -o ConnectTimeout=5 root@100.64.0.3 "top -bn1 | grep '%Cpu' | grep -oP '[0-9.]+(?= id)' | awk '{print 100 - \$1}'" 2>/dev/null || echo "ERROR")
echo "AIOPS: CPU=${aiops_cpu}%  $( [ "$(echo "$aiops_cpu > 60" | bc -l 2>/dev/null)" = "1" ] && echo 'WARN: CPU > 60%' || echo 'OK' )"

# COREDB
coredb_ram=$(ssh -o ConnectTimeout=5 root@100.64.0.4 "free -m | awk '/^Mem:/{print \$3}'" 2>/dev/null || echo "0")
echo "COREDB: RAM=${coredb_ram}MB  $( [ "$coredb_ram" -lt 4000 ] && echo 'WARN: RAM < 4GB (underutilized)' || echo 'OK' )"

echo ""
echo "--- Role Compliance ---"
for role in edge aiops coredb; do
  case $role in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
  violations=$(ssh -o ConnectTimeout=5 root@100.64.0.$ip \
    "bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --server $role --report 2>/dev/null | grep -c 'CRITICAL\|WARNING'" 2>/dev/null || echo "ERROR")
  [ "$violations" != "0" ] && { echo "FAIL: $role has $violations violations"; FAIL=1; } || echo "PASS: $role — zero violations"
done

echo ""
echo "--- Endpoint Health ---"
for url in \
  "https://wheeler.ai" \
  "https://litellm.wheeler.ai/health" \
  "https://frgops.wheeler.ai/api/health" \
  "https://predictionradar.wheeler.ai/health" \
  "https://ravynai.wheeler.ai/health" \
  "https://superset.wheeler.ai/health" \
  "https://grafana.wheeler.ai/api/health"; do
  code=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)
  [ "$code" = "200" -o "$code" = "302" ] && echo "PASS: $url → $code" || { echo "FAIL: $url → $code"; FAIL=1; }
done

echo ""
echo "--- Security ---"
# SSH hardening
for role in edge aiops coredb; do
  case $role in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
  pass_auth=$(ssh -o ConnectTimeout=5 root@100.64.0.$ip "grep '^PasswordAuthentication' /etc/ssh/sshd_config | awk '{print \$2}'" 2>/dev/null || echo "ERROR")
  [ "$pass_auth" = "no" ] && echo "PASS: $role SSH PasswordAuthentication=no" || echo "FAIL: $role SSH PasswordAuthentication=$pass_auth"
done

# UFW
for role in edge aiops coredb; do
  case $role in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
  ufw_status=$(ssh -o ConnectTimeout=5 root@100.64.0.$ip "ufw status | head -1" 2>/dev/null || echo "ERROR")
  echo "$ufw_status" | grep -q "active" && echo "PASS: $role UFW active" || { echo "FAIL: $role UFW not active"; FAIL=1; }
done

echo ""
echo "--- Backups ---"
backup_age=$(ssh root@100.64.0.4 "find /data/backups/databases/ -name '*.dump' -mtime -1 2>/dev/null | wc -l" 2>/dev/null || echo "0")
[ "$backup_age" -gt 0 ] && echo "PASS: $backup_age backup(s) within 24h" || { echo "FAIL: No recent backups"; FAIL=1; }

echo ""
echo "--- PM2 State ---"
edge_pm2=$(ssh root@100.64.0.2 "pm2 list 2>/dev/null | grep -c 'online'" 2>/dev/null || echo "ERROR")
aiops_pm2=$(ssh root@100.64.0.3 "pm2 list 2>/dev/null | grep -c 'online'" 2>/dev/null || echo "ERROR")
echo "EDGE PM2 online: $edge_pm2"
echo "AIOPS PM2 online: $aiops_pm2"

echo ""
echo "--- Docker Health ---"
for role in edge aiops coredb; do
  case $role in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
  unhealthy=$(ssh root@100.64.0.$ip "docker ps --filter 'health=unhealthy' -q | wc -l" 2>/dev/null || echo "ERROR")
  total=$(ssh root@100.64.0.$ip "docker ps -q | wc -l" 2>/dev/null || echo "ERROR")
  [ "$unhealthy" = "0" ] && echo "PASS: $role Docker $total healthy" || { echo "FAIL: $role has $unhealthy unhealthy containers"; FAIL=1; }
done

echo ""
echo "==============================================="
[ "$FAIL" = "0" ] && echo " FINAL AUDIT: ALL CHECKS PASSED" || echo " FINAL AUDIT: $FAIL FAILURES — SEE ABOVE"
echo "==============================================="
```

### Continuous Operations Handoff

| Responsibility | Owner | Cadence | First Due |
|---------------|-------|---------|-----------|
| Daily health check (3 servers) | On-call SRE | Daily 08:00 UTC | Ongoing |
| Backup verification (restore test) | On-call SRE | Monthly (1st Sunday) | Jul 5, 2026 |
| Role compliance audit (`enforce-roles.sh --report`) | On-call SRE | Weekly (Monday) | Jul 6, 2026 |
| Credential rotation | Security Lead | Quarterly | Sep 15, 2026 |
| Full DR test | SRE Team | Annually | Dec 2026 |
| Tabletop DR exercise | SRE Team + CTO | Biannually | Nov 2026 |
| Security scan (nmap + sslscan) | Security Lead | Monthly | Jul 1, 2026 |
| ARCHITECTURE.md review | SRE Lead | After any change | Continuous |

---

## 30-Day Risk Register

| Risk | Likelihood | Impact | Mitigation | Owner |
|------|-----------|--------|------------|-------|
| Hostinger CPU steal exceeds 40% again | Medium | High | Week 2: Evaluate Cloudflare Tunnel as fallback entry point. Week 4: Budget for Hetzner edge server | SRE Lead |
| AIOPS CPU exceeds 60% after absorbing all workloads | Low | Medium | Week 1-2: Monitor daily. AIOPS started at 35% with 65% idle. Headroom forecast: 20-30% used by migrations | On-call |
| COREDB remains severely underutilized | Medium | Low | After all DB migrations, tune PostgreSQL shared_buffers upward. This is not a problem — it means room to grow | DBA |
| Database migration causes application downtime | Low | High | Each migration includes 30-min verification window before decommissioning source DB. Rollback procedure documented | On-call |
| Prometheus data loss during config reload | Low | Medium | Remote write to Thanos/Cortex if 30-day retention proves insufficient. Evaluate Week 3 | SRE |
| PagerDuty alert fatigue | Medium | Medium | Week 2: Review alert thresholds with real data after 1 week of metrics. Tune or disable noisy alerts | On-call |
| Documentation drift from reality | Medium | Low | Weekly ARCHITECTURE.md review cadence. Run the IP reconciliation grep command after any change | SRE Lead |

---

## Communications

| Milestone | Audience | Message |
|-----------|----------|---------|
| Week 1 complete | #engineering | "Data consolidation complete. All databases now on COREDB. AIOPS has cache-only Redis. Zero CRITICAL violations." |
| Week 2 complete | #engineering | "Monitoring maturity achieved. 12 alert rules, 4 dashboards, PagerDuty routing tested. Logs flowing from all 3 servers." |
| Week 3 complete | #engineering + CTO | "Security hardening complete. 15 credentials rotated. UFW default-deny enforced. External scan: only 22/80/443 exposed." |
| DR test (Day 30) | #engineering | "DR test: COREDB restore successful. Row counts match. RTO: X min. RPO gap: Y hours. Report filed." |
| Day 37 final | #company | "Wheeler 3-server architecture fully stabilized and compliant. 30-day audit passed. See: /root/infrastructure/30-day-final-audit-20260629.log" |

---

**End of 30-Day Plan**
**Final document:** FINAL_STABILIZATION_CHECKLIST.md
