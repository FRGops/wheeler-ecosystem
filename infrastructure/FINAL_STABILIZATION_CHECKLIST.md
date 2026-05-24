# Wheeler Enterprise — Final Stabilization Checklist

**Target Date:** 2026-06-29 (end of 30-day plan)
**Auditor:** SRE Lead / CTO
**Sign-off Required:** Yes

This checklist defines the exact target state against which all three action plans (24-hour, 7-day, 30-day) are measured. Every item must be checked and verified with actual command output before signing off.

---

## Server Health

- [ ] **EDGE CPU steal < 20%** (currently 42.4% at T=0)
  ```bash
  ssh root@100.64.0.2 "top -bn1 | grep '%Cpu' | grep -oP '[0-9.]+(?= st)'"
  # EXPECTED: < 20.0
  ```

- [ ] **EDGE load avg < 2.0** (currently 5.13 at T=0)
  ```bash
  ssh root@100.64.0.2 "cat /proc/loadavg | cut -d' ' -f1"
  # EXPECTED: < 2.0
  ```

- [ ] **AIOPS CPU usage < 60%** (currently ~35% at T=0)
  ```bash
  ssh root@100.64.0.3 "top -bn1 | grep '%Cpu' | grep -oP '[0-9.]+(?= id)' | awk '{printf \"%.0f\", 100 - \$1}'"
  # EXPECTED: < 60
  ```

- [ ] **COREDB RAM usage > 4GB** (currently ~1.4GB at T=0 — severely underutilized)
  ```bash
  ssh root@100.64.0.4 "free -m | awk '/^Mem:/{print \$3}'"
  # EXPECTED: > 4000
  ```

- [ ] **No server swap usage > 100MB** (EDGE 0, AIOPS 0.5MB, COREDB 0 at T=0)
  ```bash
  for server in edge aiops coredb; do
    case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
    swap_mb=$(ssh root@100.64.0.$ip "free -m | awk '/^Swap:/{print \$3}'" 2>/dev/null)
    echo "$server: swap=${swap_mb}MB"
  done
  # EXPECTED: All < 100
  ```

- [ ] **EDGE disk usage < 80%**
  ```bash
  ssh root@100.64.0.2 "df -h / | awk 'NR==2{print \$5}' | tr -d '%'"
  # EXPECTED: < 80
  ```

- [ ] **AIOPS disk usage < 80%**
  ```bash
  ssh root@100.64.0.3 "df -h / | awk 'NR==2{print \$5}' | tr -d '%'"
  # EXPECTED: < 80
  ```

- [ ] **COREDB /data partition usage < 80%**
  ```bash
  ssh root@100.64.0.4 "df -h /data | awk 'NR==2{print \$5}' | tr -d '%'"
  # EXPECTED: < 80
  ```

---

## Role Compliance

### EDGE ("The Gatekeeper") — per server-role-policies.md Section 2

- [ ] **No databases on EDGE**
  ```bash
  ssh root@100.64.0.2 "docker ps --format '{{.Names}} {{.Image}}' | grep -iE 'postgres|redis|mongo|mysql|clickhouse|elastic|mariadb'"
  # EXPECTED: EMPTY
  # T=0 VIOLATION: shared-postgres-recovery running on EDGE
  ```

- [ ] **No AI/ML services on EDGE**
  ```bash
  ssh root@100.64.0.2 "docker ps --format '{{.Names}} {{.Image}}' | grep -iE 'ollama|litellm|langflow|vllm|localai|cuda|pytorch|tensorflow|transformers|gguf|ggml'"
  # EXPECTED: EMPTY
  # T=0 VIOLATION: private-ai-webui running on EDGE
  ```

- [ ] **No workers on EDGE**
  ```bash
  ssh root@100.64.0.2 "pm2 list | grep -iE 'worker|scheduler|queue|consumer|temporal|celery|sidekiq'"
  # EXPECTED: EMPTY
  # T=0 VIOLATION: prediction-radar-worker, scheduler, temporal-pipeline-worker on EDGE
  ```

- [ ] **No backup storage on EDGE**
  ```bash
  ssh root@100.64.0.2 "find / -name '*.dump' -o -name '*.pgdump' -o -name '*.sql.gz' 2>/dev/null | grep -v '/var/lib/docker' | head -5"
  # EXPECTED: EMPTY (or only config backups)
  ```

- [ ] **No application code on EDGE** (beyond static frontend builds)
  ```bash
  ssh root@100.64.0.2 "ls /root/apps/ 2>/dev/null; ls /root/services/ 2>/dev/null"
  # EXPECTED: Empty or only static site directories (no Node.js/Python runtimes running)
  ```

- [ ] **Only allowed ports on EDGE (22, 80, 443)**
  ```bash
  ssh root@100.64.0.2 "ss -tlnp | grep '0.0.0.0' | awk '{print \$4}' | grep -oP ':\d+' | sort -u"
  # EXPECTED: :22, :80, :443 (may also show :9100 bound to 100.64.0.2)
  ```

### AIOPS ("The Brain") — per server-role-policies.md Section 3

- [ ] **No primary (write-master) databases on AIOPS**
  ```bash
  ssh root@100.64.0.3 "docker ps --format '{{.Names}} {{.Image}}' | grep -iE 'postgres|redis'"
  # EXPECTED: Only read replicas or cache-only Redis with com.wheeler.role=read-replica label
  # Each must be verified: docker inspect <name> --format '{{index .Config.Labels \"com.wheeler.role\"}}'
  ```

- [ ] **No backup storage > 24 hours on AIOPS**
  ```bash
  ssh root@100.64.0.3 "find /opt/backups/ -type f -mtime +1 2>/dev/null | head -5"
  # EXPECTED: EMPTY (backups older than 24h must be on COREDB)
  ```

- [ ] **No public-facing port bindings on AIOPS (except SSH)**
  ```bash
  ssh root@100.64.0.3 "ss -tlnp | grep '0.0.0.0' | grep -v '127.0.0'"
  # EXPECTED: Only port 22 (and maybe :2375 if Docker socket — should be restricted)
  ```

- [ ] **All AIOPS services bind to Tailscale IP or localhost**
  ```bash
  ssh root@100.64.0.3 "ss -tlnp | grep -v '0.0.0.0\|127.0.0.\|100.64.0.3\|:::'"
  # EXPECTED: EMPTY (all services bound to Tailscale IP or localhost)
  ```

### COREDB ("The Vault") — per server-role-policies.md Section 4

- [ ] **No app code on COREDB**
  ```bash
  ssh root@100.64.0.4 "ls /root/apps/ 2>/dev/null; ls /root/services/ 2>/dev/null"
  # EXPECTED: EMPTY
  ```

- [ ] **No dashboards on COREDB**
  ```bash
  ssh root@100.64.0.4 "docker ps --format '{{.Names}} {{.Image}}' | grep -iE 'prometheus|grafana|loki|kibana|chronograf|superset'"
  # EXPECTED: EMPTY
  # T=0 VIOLATION: prometheus, grafana, loki running on COREDB
  ```

- [ ] **Only exporters on COREDB (node_exporter, postgres_exporter, redis_exporter)**
  ```bash
  ssh root@100.64.0.4 "docker ps --format '{{.Names}} {{.Image}}' | grep exporter"
  # EXPECTED: node_exporter, postgres_exporter, redis_exporter listed
  ```

- [ ] **No 0.0.0.0 bindings on COREDB**
  ```bash
  ssh root@100.64.0.4 "ss -tlnp | grep '0.0.0.0'"
  # EXPECTED: EMPTY
  # All services must bind to 100.64.0.4 (Tailscale) or 127.0.0.1
  ```

- [ ] **No AI/ML services on COREDB**
  ```bash
  ssh root@100.64.0.4 "docker ps --format '{{.Names}} {{.Image}}' | grep -iE 'ollama|litellm|langflow|vllm|cuda|pytorch|tensorflow|transformers|gguf'"
  # EXPECTED: EMPTY
  ```

- [ ] **No cron jobs on COREDB (except DB maintenance)**
  ```bash
  ssh root@100.64.0.4 "crontab -l 2>/dev/null"
  # EXPECTED: Only VACUUM, ANALYZE, REINDEX, backup, WAL archival, log rotation jobs
  # NO application cron jobs, data processing, API calls
  ```

- [ ] **No CI/CD on COREDB**
  ```bash
  ssh root@100.64.0.4 "docker ps --format '{{.Names}} {{.Image}}' | grep -iE 'jenkins|runner|actions'"
  # EXPECTED: EMPTY
  ```

---

## Cross-Server Communication

- [ ] **EDGE cannot reach COREDB directly** (must go through AIOPS)
  ```bash
  ssh root@100.64.0.2 "curl -s --connect-timeout 3 http://100.64.0.4:5432 2>&1; curl -s --connect-timeout 3 http://100.64.0.4:6379 2>&1"
  # EXPECTED: Connection refused, timeout, or empty response (NOT a PostgreSQL/Redis response)
  ```

- [ ] **COREDB cannot reach EDGE**
  ```bash
  ssh root@100.64.0.4 "curl -s --connect-timeout 3 http://100.64.0.2:80 2>&1"
  # EXPECTED: Connection refused or timeout
  ```

- [ ] **Tailscale ACLs restrict EDGE -> COREDB path**
  ```bash
  # Verify in Tailscale admin console:
  # - No ACL rule permits src=tag:edge dst=tag:coredb
  ```

- [ ] **Tailscale mesh fully connected (all 3 nodes)**
  ```bash
  tailscale status
  # EXPECTED: edge, aiops, coredb all show with direct connection (not via DERP relay)
  tailscale ping edge && tailscale ping aiops && tailscale ping coredb
  # EXPECTED: all pings return direct (not relayed) < 50ms
  ```

---

## Service Health

- [ ] **All PM2 apps online** (EDGE and AIOPS — no unexpected stopped processes)
  ```bash
  # EDGE
  ssh root@100.64.0.2 "pm2 list" | grep -c "online"
  # EXPECTED: 18-22 (reduced from 39 at T=0 after worker exodus)
  
  # AIOPS
  ssh root@100.64.0.3 "pm2 list" | grep -c "online"
  # EXPECTED: 19-21 (increased from 17 at T=0 with temporal workers added, backup-verification re-enabled)
  
  # Both
  ssh root@100.64.0.2 "pm2 list | grep -c 'stopped'"
  # EXPECTED: Only intentionally stopped decommissioned services (19 at T=0)
  ssh root@100.64.0.3 "pm2 list | grep -c 'stopped'"
  # EXPECTED: 0 (backup-verification re-enabled Day 4 of 7-day plan)
  ```

- [ ] **Zero PM2 errored/crash-looping processes**
  ```bash
  ssh root@100.64.0.2 "pm2 list | grep -E 'errored|restart' | grep -v '0 restarts'"
  ssh root@100.64.0.3 "pm2 list | grep -E 'errored|restart' | grep -v '0 restarts'"
  # EXPECTED: EMPTY on both
  ```

- [ ] **All Docker containers healthy**
  ```bash
  for server in edge aiops coredb; do
    case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
    echo "=== $server ==="
    ssh root@100.64.0.$ip "docker ps --filter 'health=unhealthy' --format '{{.Names}} {{.Status}}'"
  done
  # EXPECTED: Empty for all 3 (no unhealthy containers)
  ```

- [ ] **No restart loops detected**
  ```bash
  ssh root@100.64.0.3 "docker ps --format '{{.Names}} {{.Status}}' | grep -v 'Up '"
  # EXPECTED: Empty (all containers show "Up X hours/minutes")
  ```

- [ ] **All health check endpoints return 200**
  ```bash
  # Run from your workstation
  for url in \
    "https://wheeler.ai" \
    "https://litellm.wheeler.ai/health" \
    "https://frgops.wheeler.ai/api/health" \
    "https://predictionradar.wheeler.ai/health" \
    "https://ravynai.wheeler.ai/health" \
    "https://superset.wheeler.ai/health" \
    "https://grafana.wheeler.ai/api/health" \
    "https://uptime.wheeler.ai"; do
    code=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)
    echo "$url: HTTP $code"
  done
  # EXPECTED: All return 200 or 302
  ```

- [ ] **LiteLLM proxy routing AI requests**
  ```bash
  curl -s https://litellm.wheeler.ai/v1/models \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq '.data | length'
  # EXPECTED: > 0 models listed
  ```

---

## Data Architecture

- [ ] **No duplicated/conflicting databases**
  ```bash
  # Check for databases on AIOPS that also exist on COREDB
  ssh root@100.64.0.3 "docker ps --format '{{.Names}}' | grep -iE 'postgres|mysql'"
  # EXPECTED: Empty or only read replicas with com.wheeler.role=read-replica
  
  ssh root@100.64.0.4 "docker exec postgres-coredb psql -U postgres -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('template0','template1','postgres') ORDER BY datname;\""
  # EXPECTED: frgops, prediction_radar, ravynai, superset (and others as needed)
  # T=0 VIOLATION: shared-postgres-recovery on EDGE + prediction-radar-db on AIOPS + frgops-standby on AIOPS = duplicated Postgres instances
  ```

- [ ] **COREDB is single source of truth for persistent data**
  ```bash
  ssh root@100.64.0.4 "docker exec postgres-coredb pg_isready -U postgres"
  # EXPECTED: accepting connections
  ssh root@100.64.0.4 "docker exec redis-coredb redis-cli -a \$REDIS_PASSWORD PING"
  # EXPECTED: PONG
  ```

- [ ] **MinIO centralized on COREDB** (not on EDGE)
  ```bash
  # EDGE should NOT have MinIO
  ssh root@100.64.0.2 "docker ps --format '{{.Names}}' | grep -i minio"
  # EXPECTED: EMPTY (T=0: MinIO was on EDGE per architecture diagram)
  
  # COREDB should have MinIO
  ssh root@100.64.0.4 "docker ps --format '{{.Names}} {{.Status}}' | grep -i minio"
  # EXPECTED: minio-coredb "Up"
  
  # Verify MinIO health
  ssh root@100.64.0.4 "curl -s http://100.64.0.4:9000/minio/health/live"
  # EXPECTED: HTTP 200
  ```

- [ ] **Backups running from COREDB only**
  ```bash
  ssh root@100.64.0.4 "find /data/backups/databases/ -name '*.dump' -mtime -1 | wc -l"
  # EXPECTED: > 0 (at least 1 backup in last 24h)
  
  ssh root@100.64.0.3 "find /opt/backups/ -type f -name '*.dump' -mtime +1 2>/dev/null | wc -l"
  # EXPECTED: 0 (no old backups on AIOPS — all synced to COREDB)
  ```

---

## Monitoring

- [ ] **Single Prometheus instance** (on AIOPS only)
  ```bash
  ssh root@100.64.0.3 "docker ps --filter 'name=prometheus' --format '{{.Status}}'"
  # EXPECTED: "Up X hours"
  
  ssh root@100.64.0.4 "docker ps --filter 'name=prometheus' --format '{{.Status}}'"
  # EXPECTED: EMPTY
  # T=0 VIOLATION: Prometheus running on both AIOPS and COREDB
  ```

- [ ] **Single Grafana instance** (on AIOPS only)
  ```bash
  ssh root@100.64.0.3 "docker ps --filter 'name=grafana' --format '{{.Status}}'"
  # EXPECTED: "Up X hours"
  
  ssh root@100.64.0.4 "docker ps --filter 'name=grafana' --format '{{.Status}}'"
  # EXPECTED: EMPTY
  # T=0 VIOLATION: Grafana running on both AIOPS and COREDB
  ```

- [ ] **Single Loki instance** (on AIOPS only)
  ```bash
  ssh root@100.64.0.3 "docker ps --filter 'name=loki' --format '{{.Status}}'"
  # EXPECTED: "Up X hours"
  
  ssh root@100.64.0.4 "docker ps --filter 'name=loki' --format '{{.Status}}'"
  # EXPECTED: EMPTY
  # T=0 VIOLATION: Loki running on both AIOPS and COREDB
  ```

- [ ] **All exporters scraping correctly**
  ```bash
  ssh root@100.64.0.3
  curl -s http://localhost:9090/api/v1/targets | \
    jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'
  
  # EXPECTED targets (all health="up"):
  #   job=node          instance=100.64.0.2:9100     (EDGE)
  #   job=node          instance=100.64.0.3:9100     (AIOPS)
  #   job=node          instance=100.64.0.4:9100     (COREDB)
  #   job=postgres      instance=100.64.0.4:9187     (COREDB)
  #   job=redis         instance=100.64.0.4:9121     (COREDB)
  #   job=docker        instance=100.64.0.3:8080     (cAdvisor on AIOPS)
  ```

- [ ] **Alertmanager routing to Slack**
  ```bash
  # Send test alert via Alertmanager API (Day 3 of 7-day plan)
  curl -X POST http://localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{
    "labels": {"alertname": "ChecklistVerification", "severity": "info"},
    "annotations": {"summary": "Final stabilization checklist verification", "description": "Alertmanager routing verified."},
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }]'
  # EXPECTED: Alert appears in Slack #alerts channel within 30 seconds
  ```

- [ ] **Alertmanager routing to PagerDuty** (if configured)
  ```bash
  # Send test page (after configuring PagerDuty routing key)
  # EXPECTED: PagerDuty incident created
  ```

- [ ] **Loki receiving logs from all 3 servers**
  ```bash
  ssh root@100.64.0.3
  for host in edge aiops coredb; do
    count=$(curl -s "http://localhost:3100/loki/api/v1/query_range" \
      --data-urlencode "query={host=\"$host\"}" \
      --data-urlencode "limit=1" \
      --data-urlencode "start=$(date -d '1 hour ago' +%s)000000000" \
      --data-urlencode "end=$(date +%s)000000000" | \
      jq '.data.result | length' 2>/dev/null)
    echo "$host: $count log streams"
  done
  # EXPECTED: All > 0
  ```

- [ ] **Grafana dashboards loading with data**
  ```bash
  # Verify 4 standard dashboards exist and show data
  curl -s -H "Authorization: Bearer $GRAFANA_API_KEY" \
    "http://localhost:3002/api/search?type=dash-db" | jq '.[].title'
  # EXPECTED: Server Overview, Database Health, Application Health, EDGE Metrics
  ```

---

## Security

- [ ] **UFW active on all 3 servers**
  ```bash
  for server in edge aiops coredb; do
    case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
    echo -n "$server: "
    ssh root@100.64.0.$ip "ufw status | head -1" 2>/dev/null
  done
  # EXPECTED: All show "Status: active"
  ```

- [ ] **No 0.0.0.0 bindings on COREDB** (only Tailscale IP or localhost)
  ```bash
  ssh root@100.64.0.4 "ss -tlnp | grep '0.0.0.0'"
  # EXPECTED: EMPTY
  ```

- [ ] **No 0.0.0.0 bindings on AIOPS** (except SSH potentially, and ideally Tailscale-only)
  ```bash
  ssh root@100.64.0.3 "ss -tlnp | grep '0.0.0.0' | grep -v '127.0.0'"
  # EXPECTED: Only port 22 (SSH), no service ports
  ```

- [ ] **Tailscale ACLs restricting EDGE -> COREDB direct access**
  ```bash
  # Verified in Tailscale admin console
  # ACLs should match Section 5 of server-role-policies.md
  ```

- [ ] **SSH restricted to Tailscale IP on all servers**
  ```bash
  for server in edge aiops coredb; do
    case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
    echo "=== $server ==="
    ssh root@100.64.0.$ip "grep -E '^PasswordAuthentication|^PermitRootLogin|^PubkeyAuthentication' /etc/ssh/sshd_config" 2>/dev/null
  done
  # EXPECTED:
  #   PasswordAuthentication no
  #   PermitRootLogin prohibit-password (or no)
  #   PubkeyAuthentication yes
  ```

- [ ] **fail2ban active on all 3 servers**
  ```bash
  for server in edge aiops coredb; do
    case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
    echo "=== $server ==="
    ssh root@100.64.0.$ip "fail2ban-client status 2>/dev/null | grep 'Jail list'; fail2ban-client status sshd 2>/dev/null | grep -E 'Status|Currently banned'" 2>/dev/null
  done
  # EXPECTED: All show Status=active for sshd jail
  ```

- [ ] **fail2ban traefik-auth jail active on EDGE**
  ```bash
  ssh root@100.64.0.2 "fail2ban-client status traefik-auth 2>/dev/null | grep -E 'Status|Currently banned|action'"
  # EXPECTED: Jail active (protects Traefik auth endpoints from brute force)
  ```

- [ ] **No exposed Docker socket on COREDB**
  ```bash
  ssh root@100.64.0.4 "docker info 2>/dev/null | grep -i 'docker Root Dir'"
  # Verify: Docker socket is local-only, not mounted into any container
  ssh root@100.64.0.4 "docker inspect \$(docker ps -q) --format '{{.Name}}: {{range .Mounts}}{{if eq .Destination \"/var/run/docker.sock\"}}DOCKER_SOCKET_EXPOSED{{end}}{{end}}'" 2>/dev/null | grep -i "DOCKER_SOCKET"
  # EXPECTED: EMPTY
  ```

- [ ] **No secrets in plaintext on disk**
  ```bash
  for server in edge aiops coredb; do
    case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
    echo "=== $server ==="
    ssh root@100.64.0.$ip "find /root -name '.env' -o -name '*.env' | while read f; do perms=\$(stat -c '%a' \"\$f\"); [ \"\$perms\" != '600' ] && echo \"  BAD PERMS \$perms: \$f\"; done" 2>/dev/null
  done
  # EXPECTED: EMPTY (all .env files chmod 600)
  ```

- [ ] **External nmap scan shows ONLY ports 22, 80, 443 on EDGE**
  ```bash
  # Run from your workstation (NOT from any Wheeler server)
  nmap -sV -p 1-65535 187.77.148.88 2>/dev/null | grep "open"
  # EXPECTED: Only 22/tcp (ssh), 80/tcp (http), 443/tcp (https)
  # T=0: If additional ports like 5432, 6379, 3000 are open → UFW misconfigured
  ```

- [ ] **AIOPS and COREDB show zero open ports from public internet**
  ```bash
  nmap -sV -p 22,80,443,5432,6379,3000,8080,9090 5.78.140.118 2>/dev/null | grep "open"
  nmap -sV -p 22,5432,6379,9000 5.78.210.123 2>/dev/null | grep "open"
  # EXPECTED: EMPTY for both (UFW default-deny is working)
  ```

---

## Backups

- [ ] **Daily database backups verified (at least 1 test restore completed within last 7 days)**
  ```bash
  # Check backup verification log
  ssh root@100.64.0.3 "cat /var/log/backup-verification.log 2>/dev/null | tail -20"
  # EXPECTED: Recent "VERIFICATION PASSED" entry
  ```

- [ ] **All database backups < 24 hours old**
  ```bash
  ssh root@100.64.0.4 "find /data/backups/databases/ -name '*.dump' -mtime -1 | while read f; do echo \"\$(basename \$f): \$(ls -lh \$f | awk '{print \$5}')\"; done"
  # EXPECTED: At least 1 backup per database listed with non-zero size
  ```

- [ ] **Volume backups running** (if applicable)
  ```bash
  ssh root@100.64.0.4 "find /data/backups/volumes/ -mtime -7 | head -5"
  # EXPECTED: Recent volume backup tarballs
  ```

- [ ] **Off-site backup sync working**
  ```bash
  # Check sync logs (adjust path to actual sync tool: rclone, rsync, etc.)
  ssh root@100.64.0.4 "grep -i 'sync\|rclone\|offsite' /var/log/syslog 2>/dev/null | tail -5"
  # EXPECTED: Recent successful sync entries
  ```

- [ ] **Backup integrity verified (GPG signatures)**
  ```bash
  ssh root@100.64.0.4
  for f in /data/backups/databases/*.dump.gpg; do
    [ -f "${f}.sig" ] && gpg --verify "${f}.sig" "$f" 2>&1 | grep -q "Good signature" && \
      echo "PASS: $(basename $f)" || echo "FAIL: $(basename $f) — no sig or bad signature"
  done
  # EXPECTED: All show "PASS"
  ```

- [ ] **WAL archiving enabled and current**
  ```bash
  ssh root@100.64.0.4
  docker exec postgres-coredb psql -U postgres -c "SELECT archived_count, failed_count FROM pg_stat_archiver;"
  # EXPECTED: archived_count > 0, failed_count = 0
  ```

- [ ] **Backup retention policy enforced**
  ```bash
  ssh root@100.64.0.4
  echo "Daily:   $(find /data/backups/databases/ -name '*daily*' -o -mtime -1 | wc -l)"
  echo "Weekly:  $(find /data/backups/databases/ -name '*weekly*' -o -mtime -7 | wc -l)"
  echo "Monthly: $(find /data/backups/databases/ -name '*monthly*' -o -mtime -30 | wc -l)"
  # Verify against policy: 7 daily, 4 weekly, 3 monthly, 1 yearly
  ```

---

## Documentation

- [ ] **ARCHITECTURE.md updated with current service placements**
  ```bash
  grep -c "COREDB" /root/infrastructure/ARCHITECTURE.md
  # EXPECTED: > 0 (COREDB server documented)
  
  # Verify old IPs are gone:
  grep -E "100\.98\.|100\.121\.|100\.118\." /root/infrastructure/ARCHITECTURE.md
  # EXPECTED: Empty or only in historical/changelog section
  ```

- [ ] **ARCHITECTURE.md service placement matrix accurate**
  ```bash
  # FRGops PostgreSQL should show "on COREDB", not "on EDGE"
  grep -A5 "PostgreSQL.*FRGops\|FRGops.*PostgreSQL" /root/infrastructure/ARCHITECTURE.md
  ```

- [ ] **server-role-policies.md updated with any exceptions**
  ```bash
  # If any exceptions were granted during migration, they must be documented here
  grep -i "exception\|exempt" /root/infrastructure/enterprise/phase9-server-roles/server-role-policies.md
  ```

- [ ] **DR runbook reflects current topology** (correct IPs, correct service placements)
  ```bash
  # EDGE IP should be 100.64.0.2 throughout
  grep "100.98" /root/infrastructure/enterprise/phase10-documentation/disaster-recovery.md
  # EXPECTED: Empty (all 100.98.x.x references replaced)
  ```

- [ ] **Emergency contact sheet filled in** (DR runbook Section 12)
  ```bash
  grep "TO BE FILLED" /root/infrastructure/enterprise/phase10-documentation/disaster-recovery.md
  # EXPECTED: Empty (all contacts filled in)
  ```

- [ ] **All scripts reference correct Tailscale IPs** (no stale IPs: 100.98.22.10, 100.98.163.17, etc.)
  ```bash
  grep -rn "100\.98\.\|100\.121\.\|100\.118\." /root/infrastructure/ --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.js" --include="*.json" | grep -v "node_modules" | grep -v ".git" | grep -v "ARCHITECTURE.md" | grep -v "disaster-recovery.md"
  # EXPECTED: Empty or only in historical/changelog sections
  ```

- [ ] **DR runbook walkthrough completed** (tabletop exercise within last 30 days)
  ```bash
  # Look for DR test completion record
  ls -la /root/infrastructure/enterprise/phase10-documentation/dr-test-*.log 2>/dev/null
  # EXPECTED: At least 1 log from within the last 30 days
  ```

---

## Auto-Healing

- [ ] **autoheal container running on AIOPS**
  ```bash
  ssh root@100.64.0.3 "docker ps --filter 'name=autoheal' --format '{{.Status}}'"
  # EXPECTED: "Up X hours"
  ```

- [ ] **All production containers have restart policy**
  ```bash
  for server in edge aiops coredb; do
    case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
    echo "=== $server ==="
    ssh root@100.64.0.$ip "docker ps --format '{{.Names}}' | while read c; do
      policy=\$(docker inspect \"\$c\" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
      [ \"\$policy\" = \"no\" ] && echo \"  NO RESTART: \$c\"
    done"
  done
  # EXPECTED: Empty (no containers with restart=no)
  ```

- [ ] **PM2 auto-respawn working**
  ```bash
  ssh root@100.64.0.3 "pm2 list | grep -E 'errored|stopped' | grep -v backup-verification"
  # EXPECTED: Empty (no unexpected stopped/errored processes)
  ```

- [ ] **Docker daemon auto-restart enabled**
  ```bash
  for server in edge aiops coredb; do
    case $server in edge) ip=2;; aiops) ip=3;; coredb) ip=4;; esac
    echo -n "$server: "
    ssh root@100.64.0.$ip "systemctl show docker -p Restart 2>/dev/null | cut -d= -f2"
  done
  # EXPECTED: All show "on-failure" or "always"
  ```

---

## Performance

- [ ] **API response P95 < 2 seconds** (all services)
  ```bash
  ssh root@100.64.0.3
  curl -s "http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket[5m]))" | \
    jq '.data.result[] | {service: .metric.service, p95: .value[1]}'
  # EXPECTED: All < 2.0 seconds
  ```

- [ ] **Queue depth stable** (not growing indefinitely)
  ```bash
  ssh root@100.64.0.3
  # Check BullMQ queue depths (adjust key pattern as needed)
  docker exec redis-aio redis-cli -a "$REDIS_PASSWORD" KEYS "bull:*:waiting" 2>/dev/null | wc -l
  docker exec redis-aio redis-cli -a "$REDIS_PASSWORD" KEYS "bull:*:failed" 2>/dev/null | wc -l
  # EXPECTED: failed=0, waiting < 100 (or decreasing trend)
  ```

- [ ] **No database connection pool exhaustion**
  ```bash
  ssh root@100.64.0.4
  docker exec postgres-coredb psql -U postgres -c \
    "SELECT count(*) AS total_connections, 
            (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max_connections,
            round(count(*) * 100.0 / (SELECT setting::int FROM pg_settings WHERE name='max_connections'), 1) AS pct_used
     FROM pg_stat_activity;"
  # EXPECTED: pct_used < 80%
  ```

- [ ] **No query latency anomalies**
  ```bash
  ssh root@100.64.0.4
  docker exec postgres-coredb psql -U postgres -c \
    "SELECT query, mean_exec_time, calls 
     FROM pg_stat_statements 
     WHERE mean_exec_time > 1000  -- queries averaging > 1 second
     ORDER BY mean_exec_time DESC 
     LIMIT 10;"
  # EXPECTED: Empty or only known-slow reporting queries
  ```

---

## Change Control

- [ ] **All migrations approved** (per server-role-policies.md Section 9 change control process)
  - [ ] Proposal documented for each service move
  - [ ] Security review completed
  - [ ] Policy updated BEFORE move
  - [ ] Enforcement script updated
  - [ ] Labels applied to new containers
  - [ ] Audit passed (zero CRITICAL violations)
  - [ ] 72-hour monitoring completed

- [ ] **Unapproved changes in last 30 days: 0**
  ```bash
  # Review git log of infrastructure repo
  cd /root/infrastructure && git log --oneline --since="2026-05-23" | head -20
  # Every commit should correspond to a planned migration from these action plans
  ```

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| SRE Lead | [TO BE FILLED] | [TO BE FILLED] | ______________ |
| CTO | [TO BE FILLED] | [TO BE FILLED] | ______________ |
| Security Lead | [TO BE FILLED] | [TO BE FILLED] | ______________ |
| DBA (if applicable) | [TO BE FILLED] | [TO BE FILLED] | ______________ |

### Sign-off Criteria

All items above must be checked. Any unchecked item requires a written exception documented below.

**Exceptions:**

| Item | Reason Not Met | Risk Accepted | Date to Revisit |
|------|---------------|---------------|-----------------|
| (none expected) | | | |

---

**Checklist Version:** 1.0.0
**Last Updated:** 2026-05-23
**Next Review:** 2026-06-29 (end of 30-day plan, concurrent with sign-off)
