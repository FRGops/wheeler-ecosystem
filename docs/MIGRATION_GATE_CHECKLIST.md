# Wheeler Ecosystem — Migration Gate Checklist

| | |
|---|---|
| **Document ID** | WHL-MIG-GATE-v1.0 |
| **Classification** | Internal — Production Operations |
| **Owner** | Principal Production Readiness Auditor |
| **Last Updated** | 2026-05-23 |
| **Applies To** | All service migrations across EDGE, AIOPS, and COREDB nodes |

---

## Table of Contents

1. [Infrastructure Overview](#infrastructure-overview)
2. [Gate Structure & Rules](#gate-structure--rules)
3. [Gate 1 — Source Service Healthy Before Copy](#gate-1--source-service-healthy-before-copy)
4. [Gate 2 — Backup Exists](#gate-2--backup-exists)
5. [Gate 3 — Target Service Starts](#gate-3--target-service-starts)
6. [Gate 4 — Target Health Passes](#gate-4--target-health-passes)
7. [Gate 5 — Dependency Tests Pass](#gate-5--dependency-tests-pass)
8. [Gate 6 — Public Route Can Switch](#gate-6--public-route-can-switch)
9. [Gate 7 — Rollback Command Exists](#gate-7--rollback-command-exists)
10. [Gate 8 — Old Service Stopped Only After New Verified](#gate-8--old-service-stopped-only-after-new-service-verified)
11. [Gate 9 — 24-Hour Monitoring Passed](#gate-9--24-hour-monitoring-passed)
12. [Migration Gate Summary Matrix](#migration-gate-summary-matrix)
13. [Emergency Migration Override Procedure](#emergency-migration-override-procedure)
14. [Post-Migration Validation Checklist](#post-migration-validation-checklist)
15. [Migration Log Template](#migration-log-template)

---

## Infrastructure Overview

The Wheeler ecosystem is distributed across three physical nodes. Every service migration must account for the source and target node topology.

### EDGE NODE
| Property | Value |
|---|---|
| **Provider** | Hostinger |
| **IP Address** | 187.77.148.88 |
| **Role** | Public routing, frontends, SSL termination, dashboards |
| **Typical Services** | Nginx, Traefik, Cloudflare Tunnel, Grafana (public), static assets, WAF |

### AIOPS NODE
| Property | Value |
|---|---|
| **Provider** | Hetzner |
| **IP Address** | 5.78.140.118 |
| **Role** | APIs, AI workers, agents, compute workloads |
| **Typical Services** | FastAPI/Express backends, Celery workers, LangChain agents, inference runners, webhook handlers |

### COREDB NODE
| Property | Value |
|---|---|
| **Provider** | Hetzner |
| **IP Address** | 5.78.210.123 |
| **Role** | Databases, caches, storage, backups |
| **Typical Services** | PostgreSQL, Redis/Valkey, MinIO/S3, MongoDB, backup agents, replication slots |

> **CRITICAL:** Know which node is source and which is target before beginning any migration. Cross-node migrations have additional networking prerequisites that same-node migrations do not.

---

## Gate Structure & Rules

### Cardinal Rule

> **A migration SHALL NOT proceed to Gate N+1 until Gate N has passed with an explicit sign-off.**

### Enforcement

1. Each gate is gated in CI/CD pipeline or manual runbook depending on maturity.
2. The Migration Accountability Record (MAR) must be initialized before Gate 1 and updated after every gate.
3. Any gate that fails three or more times triggers a **Migration Readiness Review** with the SRE Lead and Engineering Manager.
4. All artifacts (command output, screenshots, logs, checksums) must be archived to the migration run folder:
   ```
   /var/log/wheeler/migrations/<service-name>/<YYYY-MM-DD>/gate-<N>/
   ```

### Gate Lifecycle State Machine

```
[PENDING] --> [IN PROGRESS] --> [PASSED] --> Gate N+1
                           \-> [FAILED] --> [RETRY] --> [IN PROGRESS]
                                       \-> [WAIVED] --> Gate N+1 (emergency only)
```

---

## Gate 1 — Source Service Healthy Before Copy

**Prerequisite:** Migration Accountability Record initialized.

### Why This Matters

A migration that starts from an unhealthy source will copy corrupted state, mask pre-existing problems, and make rollback unreliable. Source health is the foundation.

### Checklist

- [ ] **G1.1** — Process is online and not in a crash loop
- [ ] **G1.2** — All configured ports are listening on expected interfaces
- [ ] **G1.3** — Health endpoint returns HTTP 200 with valid response body
- [ ] **G1.4** — No crash loop detected (restart count < 3 in last 60 minutes)
- [ ] **G1.5** — All declared dependencies are reachable from the source node
- [ ] **G1.6** — Disk usage on source volume is below 85%
- [ ] **G1.7** — System load average is within normal operating range (< 70% of CPU count)

### Verification Procedure

#### Step 1: Check Process Status

```bash
# For PM2-managed services
ssh <source-node> "pm2 status <service-name>"

# For Docker-managed services
ssh <source-node> "docker ps --filter name=<service-name> --format '{{.Status}}'"

# For systemd-managed services
ssh <source-node> "systemctl status <service-name> --no-pager"
```

**Expected output:** Process status shows `online` (PM2), `Up <duration>` (Docker), or `active (running)` (systemd).

#### Step 2: Verify Port Binding

```bash
ssh <source-node> "ss -tlnp | grep -E '<port1>|<port2>'"
```

**Expected output:** Each expected port is listed with `LISTEN` state and the correct process name.

#### Step 3: Health Endpoint Check

```bash
ssh <source-node> "curl -s -o /dev/null -w '%{http_code}' http://localhost:<health-port>/health"
ssh <source-node> "curl -s http://localhost:<health-port>/health | jq ."
```

**Expected output:** HTTP `200`, JSON body with `status: "ok"` or equivalent.

#### Step 4: Crash Loop Detection

```bash
# PM2
ssh <source-node> "pm2 list | grep <service-name> | awk '{print \$18}'"

# Docker
ssh <source-node> "docker inspect <container-name> --format '{{.RestartCount}}'"

# systemd
ssh <source-node> "journalctl -u <service-name> --since '60 min ago' | grep -c 'Started'"
```

**Expected output:** Restart count < 3.

#### Step 5: Dependency Reachability

```bash
ssh <source-node> "/usr/local/bin/wheeler-check-deps <service-name>"
```

**Expected output:** All dependencies marked `REACHABLE`.

### Pass/Fail Criteria

| Criteria | Threshold |
|---|---|
| Process state | `online` / `Up` / `active (running)` |
| Ports listening | All declared ports in `LISTEN` |
| Health endpoint | HTTP 200, valid JSON |
| Restart count | < 3 in 60 minutes |
| Dependencies | 100% reachable |
| Disk usage | < 85% |
| Load average | < 70% of CPU count |

### Required Artifacts

- [ ] Health check raw output (stdout + stderr)
- [ ] PM2/Docker/systemd status output
- [ ] Dependency test results (`wheeler-check-deps` output)
- [ ] `ss -tlnp` output for port verification

### Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **QA Engineer** | | |

### Rollback

Not applicable — migration has not started. Simply abort the migration plan.

### Automated Check Script

```
/usr/local/bin/wheeler-migrate gate1 --service <service-name> --source <source-node>
```

---

## Gate 2 — Backup Exists

**Prerequisite:** Gate 1 passed.

### Why This Matters

Backups are the last-resort recovery mechanism. A migration without a verified backup is a data-loss incident waiting to happen. This gate ensures reversible state.

### Checklist

- [ ] **G2.1** — Database dump/snapshot less than 24 hours old
- [ ] **G2.2** — Configuration files backed up (including environment-specific overrides)
- [ ] **G2.3** — Environment variables documented and exported to secure vault
- [ ] **G2.4** — SSL/TLS certificates and keys backed up (if terminating on this node)
- [ ] **G2.5** — Persistent volume / data directory backup completed
- [ ] **G2.6** — Backup checksum calculated and verified
- [ ] **G2.7** — Backup integrity check passed (test restore on sandbox if applicable)

### Verification Procedure

#### Step 1: Initiate Database Backup

```bash
# PostgreSQL
ssh <source-node> "pg_dump -U <user> -h localhost <database> \
  | gzip > /backups/<service-name>/db-$(date +%Y%m%d-%H%M%S).sql.gz"

# MongoDB
ssh <source-node> "mongodump --uri=mongodb://localhost:27017/<database> \
  --archive=/backups/<service-name>/mongo-$(date +%Y%m%d-%H%M%S).archive --gzip"

# Redis (AOF/RDB file copy)
ssh <source-node> "redis-cli BGSAVE && cp /var/lib/redis/dump.rdb \
  /backups/<service-name>/redis-$(date +%Y%m%d-%H%M%S).rdb"
```

**Expected output:** Backup command exits 0; backup file exists and size > 0.

#### Step 2: Verify Backup Freshness

```bash
ssh <source-node> "find /backups/<service-name>/ -type f -mtime -1 | wc -l"
```

**Expected output:** Count >= number of expected backup artifacts.

#### Step 3: Calculate Checksum

```bash
ssh <source-node> "sha256sum /backups/<service-name>/* > /backups/<service-name>/checksums.sha256"
ssh <source-node> "sha256sum -c /backups/<service-name>/checksums.sha256"
```

**Expected output:** All files: `OK`.

#### Step 4: Backup Configuration Files

```bash
ssh <source-node> "tar czf /backups/<service-name>/config-$(date +%Y%m%d-%H%M%S).tgz \
  /etc/<service-name>/ \
  /opt/<service-name>/.env \
  /opt/<service-name>/config.*"
```

**Expected output:** tar exits 0; archive size reported.

#### Step 5: Backup SSL Certificates (if applicable)

```bash
ssh <source-node> "tar czf /backups/<service-name>/ssl-$(date +%Y%m%d-%H%M%S).tgz \
  /etc/letsencrypt/live/<domain>/ \
  /etc/ssl/<service-name>/"
```

**Expected output:** tar exits 0; archive contains certificate files.

#### Step 6: Document Environment Variables

```bash
ssh <source-node> "/usr/local/bin/wheeler-export-env <service-name> > /backups/<service-name>/env-$(date +%Y%m%d-%H%M%S).json"
```

**Expected output:** Valid JSON file with key-value pairs (secrets masked).

#### Step 7: Backup Integrity Test

```bash
ssh <sandbox-node> "/usr/local/bin/wheeler-restore-test \
  --backup-path /backups/<service-name>/latest/ \
  --sandbox"
```

**Expected output:** Restore test passes; service starts and responds in sandbox.

### Pass/Fail Criteria

| Criteria | Threshold |
|---|---|
| Backup age | < 24 hours |
| Backup size | > 0 bytes, within 30% of expected size |
| Checksum verification | All files pass |
| Config backup | Contains all declared config paths |
| SSL backup | All certificates present (if applicable) |
| Env var export | Valid JSON, no empty values for required vars |
| Integrity test | Sandbox restore succeeds |

### Required Artifacts

- [ ] Backup file paths with timestamps
- [ ] Backup size for each artifact (bytes)
- [ ] SHA-256 checksums file
- [ ] Env var export (masked) JSON
- [ ] Sandbox restore test output

### Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **SRE** | | |

### Rollback

Delete incomplete or corrupt backup files from `/backups/<service-name>/`. Re-run the backup procedure.

### Automated Check Script

```
/usr/local/bin/wheeler-migrate gate2 --service <service-name> --source <source-node>
```

---

## Gate 3 — Target Service Starts

**Prerequisite:** Gate 2 passed.

### Why This Matters

If the service cannot start on the target node, the migration is dead in the water. This gate catches installation issues, port conflicts, and binary incompatibilities before any traffic is routed.

### Checklist

- [ ] **G3.1** — Service binary/package installed on target node (correct version)
- [ ] **G3.2** — Process starts without fatal errors
- [ ] **G3.3** — All declared ports bind correctly on target
- [ ] **G3.4** — No port conflicts with existing services on target
- [ ] **G3.5** — Firewall rules allow traffic on required ports (internal and/or external)
- [ ] **G3.6** — Service runs under the correct user (not root unless explicitly required)

### Verification Procedure

#### Step 1: Verify Installation

```bash
ssh <target-node> "which <service-binary> && <service-binary> --version"
# OR
ssh <target-node> "docker images <service-name> --format '{{.Tag}}'"
```

**Expected output:** Binary path and version match source; Docker image tag matches expected.

#### Step 2: Start Service

```bash
# PM2
ssh <target-node> "pm2 start /opt/<service-name>/ecosystem.config.js --only <service-name>"

# Docker Compose
ssh <target-node> "cd /opt/<service-name> && docker compose up -d"

# systemd
ssh <target-node> "systemctl start <service-name>"
```

**Expected output:** Start command exits 0; no `FATAL` or `ERROR` lines in immediate output.

#### Step 3: Confirm Process Running

```bash
ssh <target-node> "pm2 status <service-name>"
ssh <target-node> "docker ps --filter name=<service-name>"
ssh <target-node> "systemctl is-active <service-name>"
```

**Expected output:** `online` / `Up` / `active`.

#### Step 4: Verify Port Binding

```bash
ssh <target-node> "ss -tlnp | grep <service-name>"
```

**Expected output:** Expected ports listed in `LISTEN` state with correct process name.

#### Step 5: Check for Port Conflicts

```bash
ssh <target-node> "/usr/local/bin/wheeler-check-ports <service-name>"
```

**Expected output:** No `CONFLICT` entries for any declared port.

#### Step 6: Verify Firewall Rules

```bash
# UFW
ssh <target-node> "ufw status verbose | grep -E '<port>'"

# iptables
ssh <target-node> "iptables -L INPUT -v -n | grep -E '<port>'"

# firewalld
ssh <target-node> "firewall-cmd --list-all | grep -E '<port>'"
```

**Expected output:** Expected ports appear with `ALLOW` or `ACCEPT`.

#### Step 7: Verify Running User

```bash
ssh <target-node> "ps aux | grep <service-name> | grep -v grep | awk '{print \$1}'"
```

**Expected output:** Expected non-root user (e.g., `wheeler`, `www-data`).

### Pass/Fail Criteria

| Criteria | Threshold |
|---|---|
| Service installed | Correct version on target |
| Start success | Exit code 0, no fatal errors |
| Process running | Confirmed by process manager |
| Port binding | All declared ports in LISTEN on target |
| Port conflicts | Zero conflicts detected |
| Firewall | All required ports allowed |
| Running user | Non-root (unless waived) |

### Required Artifacts

- [ ] Start command output (stdout + stderr)
- [ ] Port check output (`ss -tlnp`)
- [ ] Process list showing service PID and user
- [ ] Firewall rule verification output

### Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **SRE** | | |

### Rollback

```bash
ssh <target-node> "pm2 stop <service-name> && pm2 delete <service-name>"
# OR
ssh <target-node> "docker compose -f /opt/<service-name>/docker-compose.yml down"
# OR
ssh <target-node> "systemctl stop <service-name> && systemctl disable <service-name>"
```

### Automated Check Script

```
/usr/local/bin/wheeler-migrate gate3 --service <service-name> --target <target-node>
```

---

## Gate 4 — Target Health Passes

**Prerequisite:** Gate 3 passed.

### Why This Matters

Starting is not the same as being healthy. A service that starts but immediately enters a degraded state, spews errors, or responds sluggishly is not ready for traffic.

### Checklist

- [ ] **G4.1** — Health endpoint returns HTTP 200
- [ ] **G4.2** — Health response body is valid and contains expected fields
- [ ] **G4.3** — Health endpoint response time is under 2 seconds
- [ ] **G4.4** — Startup logs show clean initialization (no SEVERE/FATAL entries)
- [ ] **G4.5** — No ERROR-level log entries in the first 60 seconds after start (excluding benign warnings)
- [ ] **G4.6** — Memory footprint is within expected range (compare to source)

### Verification Procedure

#### Step 1: Health Endpoint — HTTP Status

```bash
ssh <target-node> "curl -s -o /dev/null -w '%{http_code}' http://localhost:<health-port>/health"
```

**Expected output:** `200`.

#### Step 2: Health Endpoint — Response Body

```bash
ssh <target-node> "curl -s http://localhost:<health-port>/health | jq ."
```

**Expected output:** Valid JSON; `status` field is `ok` or `healthy`; any dependency status fields are `up`.

#### Step 3: Health Endpoint — Response Time

```bash
ssh <target-node> "curl -s -o /dev/null -w 'time_total: %{time_total}s' http://localhost:<health-port>/health"
```

**Expected output:** `time_total: < 2.000s`.

#### Step 4: Startup Log Check

```bash
# PM2
ssh <target-node> "pm2 logs <service-name> --nostream --lines 50"

# Docker
ssh <target-node> "docker logs <container-name> --tail 50"

# systemd
ssh <target-node> "journalctl -u <service-name> --since '2 min ago' --no-pager"
```

**Expected output:** No `SEVERE`, `FATAL`, `PANIC`, or `CRITICAL` entries. Startup sequence completes with `ready`, `listening`, or `started` message.

#### Step 5: Error Log Scan (First 60 Seconds)

```bash
# Scan logs from the first 60 seconds after PID creation
ssh <target-node> "/usr/local/bin/wheeler-log-scan --service <service-name> --window 60 --level ERROR"
```

**Expected output:** `0 error-level entries found in window` (or a pre-approved exception list matches only).

#### Step 6: Memory Footprint

```bash
ssh <target-node> "ps -o pid,rss,comm -p \$(pgrep -f <service-name>) | tail -1 | awk '{print \$2}'"
```

Compare to source:
```bash
ssh <source-node> "ps -o pid,rss,comm -p \$(pgrep -f <service-name>) | tail -1 | awk '{print \$2}'"
```

**Expected output:** Target RSS within ±25% of source RSS.

### Pass/Fail Criteria

| Criteria | Threshold |
|---|---|
| Health status code | HTTP 200 |
| Health body | Valid JSON, `status: ok/healthy` |
| Health latency | < 2.0 seconds |
| Startup logs | No SEVERE/FATAL/PANIC |
| Error log entries | 0 in first 60s (or approved exception) |
| Memory footprint | Within ±25% of source |

### Required Artifacts

- [ ] Health check curl output (headers + body)
- [ ] Health check timing measurement
- [ ] Log excerpt (first 60 seconds, full text)
- [ ] Memory comparison (source vs target RSS)

### Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **QA Engineer** | | |

### Rollback

```bash
ssh <target-node> "pm2 stop <service-name>"
```
Investigate root cause before retrying. Do not proceed until health is clean.

### Automated Check Script

```
/usr/local/bin/wheeler-migrate gate4 --service <service-name> --target <target-node>
```

---

## Gate 5 — Dependency Tests Pass

**Prerequisite:** Gate 4 passed.

### Why This Matters

A service may appear healthy in isolation but fail when talking to its actual dependencies. Network policies, credential mismatches, and version incompatibilities surface here.

### Checklist

- [ ] **G5.1** — Database connection established and query returns results
- [ ] **G5.2** — Redis/Valkey connection established and PING returns PONG
- [ ] **G5.3** — AI/service endpoints reachable with valid response
- [ ] **G5.4** — External/third-party APIs reachable
- [ ] **G5.5** — File/object storage accessible (read + write test)
- [ ] **G5.6** — DNS resolution works for all internal and external hostnames
- [ ] **G5.7** — Message queue connection established (RabbitMQ/NATS/Kafka if applicable)

### Verification Procedure

#### Step 1: Database Connectivity

```bash
# PostgreSQL
ssh <target-node> "PGPASSWORD='<password>' psql -h <db-host> -U <user> -d <database> -c 'SELECT 1 AS connectivity_test;'"

# MongoDB
ssh <target-node> "mongosh 'mongodb://<user>:<password>@<db-host>:27017/<database>' --eval 'db.runCommand({ping: 1})'"

# MySQL/MariaDB
ssh <target-node> "mysql -h <db-host> -u <user> -p'<password>' -e 'SELECT 1 AS connectivity_test;'"
```

**Expected output:** Query returns result without error.

#### Step 2: Redis Connectivity

```bash
ssh <target-node> "redis-cli -h <redis-host> -p <redis-port> -a '<password>' --no-auth-warning PING"
```

**Expected output:** `PONG`.

#### Step 3: Internal Service Endpoints

```bash
ssh <target-node> "curl -s -o /dev/null -w '%{http_code}' http://<internal-service>:<port>/health"
```

**Expected output:** `200` for each declared internal dependency.

#### Step 4: External API Reachability

```bash
ssh <target-node> "curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://<external-api>/status"
```

**Expected output:** `200` or expected status code from rate-limited endpoints (`403` with valid body is acceptable for some APIs).

#### Step 5: File Storage Read/Write

```bash
# S3/MinIO
ssh <target-node> "aws s3 ls s3://<bucket>/ --endpoint-url https://<storage-host> --max-items 1"

# POSIX filesystem
ssh <target-node> "touch /mnt/<storage>/<service-name>/test-write && \
  echo 'test' > /mnt/<storage>/<service-name>/test-write && \
  cat /mnt/<storage>/<service-name>/test-write && \
  rm /mnt/<storage>/<service-name>/test-write"
```

**Expected output:** List succeeds; write/read/delete cycle completes without error.

#### Step 6: DNS Resolution

```bash
ssh <target-node> "for host in <db-host> <redis-host> <api-host> <external-host>; do
  echo -n \"\$host: \"
  dig +short \$host || nslookup \$host | grep Address
done"
```

**Expected output:** Each hostname resolves to at least one IP address.

#### Step 7: Message Queue (if applicable)

```bash
# RabbitMQ
ssh <target-node> "rabbitmqctl -n <node-name> status | grep -q 'uptime' && echo 'CONNECTED'"

# NATS
ssh <target-node> "nats-ping -s nats://<nats-host>:4222"
```

**Expected output:** `CONNECTED` or successful ping.

### Pass/Fail Criteria

| Criteria | Threshold |
|---|---|
| Database | Query executes, returns data |
| Redis | PING returns PONG |
| Internal endpoints | All return 200 |
| External APIs | All reachable (or known-status response) |
| File storage | Read + write + delete cycle clean |
| DNS | All hostnames resolve |
| Message queue | Connected and responsive |

### Required Artifacts

- [ ] Connectivity test output for each dependency
- [ ] DNS resolution output for all hostnames
- [ ] Storage read/write test output

### Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **SRE** | | |
| **QA Engineer** | | |

### Rollback

```bash
ssh <target-node> "pm2 stop <service-name>"
```
Diagnose connectivity failures. Common causes: firewall rules, DNS misconfiguration, credential rotation, IP allowlist not updated.

### Automated Check Script

```
/usr/local/bin/wheeler-migrate gate5 --service <service-name> --target <target-node>
```

---

## Gate 6 — Public Route Can Switch

**Prerequisite:** Gate 5 passed.

### Why This Matters

Internal health means nothing if external traffic cannot reach the new service. This gate validates the entire public routing chain: DNS, edge proxy, SSL, and load balancing.

### Checklist

- [ ] **G6.1** — DNS record configured with low TTL (<= 300 seconds) pointing to the correct edge entrypoint
- [ ] **G6.2** — Cloudflare configuration prepared (orange-cloud or gray-cloud as appropriate, page rules updated)
- [ ] **G6.3** — Proxy configuration prepared for target route (Nginx server block / Traefik router)
- [ ] **G6.4** — SSL/TLS certificate valid for the target route (no expiry < 30 days)
- [ ] **G6.5** — Load balancer configuration updated (if applicable; backend pool includes target)
- [ ] **G6.6** — Dry-run traffic test from external IP reaches the target service
- [ ] **G6.7** — WAF / security rules updated for the new route

### Verification Procedure

#### Step 1: DNS Record Verification

```bash
dig +short <service-domain> @1.1.1.1
dig +short <service-domain> @8.8.8.8
dig <service-domain> | grep -E '^\s+.*IN\s+A' | head -5
```

**Expected output:** A record points to EDGE node public IP (187.77.148.88) or Cloudflare proxy IP. TTL <= 300.

#### Step 2: Cloudflare Configuration

```bash
# Verify Cloudflare proxy status
curl -s -H "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records?name=<service-domain>" | jq .
```

**Expected output:** DNS record exists with correct `proxied` setting. SSL mode is `full` or `full (strict)`.

#### Step 3: Proxy Config Validation

```bash
# Nginx
ssh <edge-node> "nginx -t"

# Traefik
ssh <edge-node> "traefik --configfile=/etc/traefik/traefik.yml --check-config"
```

**Expected output:** `syntax is ok` / `configuration is valid`.

#### Step 4: Verify Proxy Config Points to Target

```bash
# Check the upstream/server block points to the correct target IP:port
ssh <edge-node> "grep -A 10 '<service-domain>' /etc/nginx/sites-enabled/*.conf | grep -E 'proxy_pass|server'"
```

**Expected output:** Upstream points to target node IP and correct port.

#### Step 5: SSL Certificate Validation

```bash
# Check certificate expiry for the target domain
echo | openssl s_client -servername <service-domain> -connect <target-node>:<port> 2>/dev/null \
  | openssl x509 -noout -dates -subject -issuer
```

**Expected output:** `notAfter` date is > 30 days from today. Subject matches expected domain.

#### Step 6: Dry-Run External Traffic Test

```bash
# Simulate external request through the edge proxy
curl -s -o /dev/null -w 'HTTP %{http_code} in %{time_total}s' \
  -H "Host: <service-domain>" \
  http://<edge-node-ip>:<proxy-port>/<health-path>
```

**Expected output:** `HTTP 200` or expected response code. Response time < 5 seconds.

#### Step 7: Load Balancer Pool Verification

```bash
# If using HAProxy, Nginx upstream, or external LB
ssh <lb-node> "/usr/local/bin/wheeler-check-lb-pool <service-name>"
```

**Expected output:** Target node appears in backend pool with `UP` status.

#### Step 8: Proxy Config Diff Review

Generate and review diff:
```bash
diff <(ssh <edge-node> "cat /etc/nginx/sites-enabled/<service-name>.conf.bak") \
     <(ssh <edge-node> "cat /etc/nginx/sites-enabled/<service-name>.conf")
```

**Expected output:** Only the upstream address changed (old IP -> new IP). No other changes to routing, headers, timeouts, or SSL settings.

### Pass/Fail Criteria

| Criteria | Threshold |
|---|---|
| DNS TTL | <= 300 seconds |
| DNS target | EDGE node IP or Cloudflare proxy |
| Proxy config | Validated by config check tool |
| Upstream target | Points to target node:port |
| SSL expiry | > 30 days |
| Dry-run traffic | 200 (or expected) from external |
| LB pool | Target node UP |
| Config diff | Contains only intended changes |

### Required Artifacts

- [ ] DNS `dig` output (multiple resolvers)
- [ ] Cloudflare config API response (screenshot acceptable)
- [ ] Proxy config diff (diff output or side-by-side screenshot)
- [ ] SSL certificate dates output
- [ ] Dry-run traffic test output

### Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **SRE** | | |
| **Network Engineer** | | |

### Rollback

```bash
# Revert proxy config
ssh <edge-node> "cp /etc/nginx/sites-enabled/<service-name>.conf.bak \
  /etc/nginx/sites-enabled/<service-name>.conf && nginx -s reload"

# Revert Cloudflare config if changed
curl -s -X PUT -H "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records/<record-id>" \
  -H "Content-Type: application/json" \
  --data '{"type":"A","name":"<domain>","content":"<old-ip>","ttl":300,"proxied":true}'
```

### Automated Check Script

```
/usr/local/bin/wheeler-migrate gate6 --service <service-name> --target <target-node> --edge <edge-node>
```

---

## Gate 7 — Rollback Command Exists

**Prerequisite:** Gate 6 passed.

### Why This Matters

> **"If you cannot roll back in under 5 minutes, you are not ready to migrate."**

This gate is non-negotiable. A tested, timed rollback is the difference between a routine migration and an extended outage.

### Checklist

- [ ] **G7.1** — Rollback script exists at a known, absolute path
- [ ] **G7.2** — Rollback script is idempotent (can run multiple times safely)
- [ ] **G7.3** — Rollback has been tested in staging environment within last 7 days
- [ ] **G7.4** — End-to-end rollback completes in under 5 minutes
- [ ] **G7.5** — Data consistency after rollback verified (no corruption, no lost writes)
- [ ] **G7.6** — Notification template prepared for rollback communication
- [ ] **G7.7** — All sign-off authorities know how to trigger the rollback

### Verification Procedure

#### Step 1: Verify Rollback Script Exists

```bash
ls -l /opt/wheeler/rollback/<service-name>/rollback.sh
file /opt/wheeler/rollback/<service-name>/rollback.sh
```

**Expected output:** File exists, is executable, is a shell script.

#### Step 2: Review Rollback Script Idempotency

```bash
bash -n /opt/wheeler/rollback/<service-name>/rollback.sh
grep -E 'set -[euo]' /opt/wheeler/rollback/<service-name>/rollback.sh
```

**Expected output:** Script passes syntax check; includes `set -euo pipefail` or equivalent error handling. Script contains guard clauses that skip steps already completed.

#### Step 3: Execute Rollback in Staging

```bash
# On staging environment
ssh <staging-node> "/opt/wheeler/rollback/<service-name>/rollback.sh --dry-run"
ssh <staging-node> "time /opt/wheeler/rollback/<service-name>/rollback.sh --full"
```

**Expected output:** Dry run lists all steps clearly. Full run completes with exit 0. `time` output shows elapsed < 300 seconds (5 minutes).

#### Step 4: Verify Data Consistency Post-Rollback

```bash
ssh <staging-node> "/usr/local/bin/wheeler-verify-consistency <service-name> \
  --pre-snapshot /backups/<service-name>/pre-migrate/ \
  --post-rollback"
```

**Expected output:** `CONSISTENCY CHECK: PASSED`. Row counts, checksums, and schema match.

#### Step 5: Validate Notification Template

```bash
cat /opt/wheeler/rollback/<service-name>/rollback-notification.md
```

**Expected output:** Template contains: service name, affected users, impact description, rollback reason field, rollback duration field, contact information, and post-mortem schedule.

### Pass/Fail Criteria

| Criteria | Threshold |
|---|---|
| Script exists | Yes, executable, at known path |
| Script idempotent | Multiple runs produce same end state |
| Staging test | Passed within last 7 days |
| Rollback time | < 5 minutes (300 seconds) |
| Data consistency | PASSED after rollback |
| Notification template | Complete and reviewed |

### Required Artifacts

- [ ] Rollback script absolute path
- [ ] Staging test output (stdout + stderr + `time`)
- [ ] Data consistency verification output
- [ ] Notification template copy

### Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **SRE Lead** | | |

### Rollback

> **The rollback IS the rollback for this gate.** If the rollback script itself fails in staging, fix the script and retest. Do not proceed until it passes.

### Automated Check Script

```
/usr/local/bin/wheeler-migrate gate7 --service <service-name> --target <target-node>
```

---

## Gate 8 — Old Service Stopped Only After New Verified

**Prerequisite:** Gate 7 passed.

### Why This Matters

The most dangerous moment in any migration is cutting over traffic. The old service must remain alive and drainable until the new service has proven itself under real user load. This gate implements a **soft cutover** with a safety net.

### Checklist

- [ ] **G8.1** — Traffic is visibly flowing to the new service (access logs show real requests)
- [ ] **G8.2** — Health checks on new service passing continuously for at least 5 minutes
- [ ] **G8.3** — No user-reported errors or incidents since traffic cutover
- [ ] **G8.4** — Old service is still running but drained of new connections
- [ ] **G8.5** — Revert path confirmed: can instantly re-enable old route (single command)
- [ ] **G8.6** — Error rate on new service is <= baseline error rate on old service
- [ ] **G8.7** — Response time on new service is <= 1.2x old service response time

### Verification Procedure

#### Step 1: Verify Traffic Flow to New Service

```bash
# Check access logs on new service for last 5 minutes
ssh <target-node> "tail -100 /var/log/<service-name>/access.log"
ssh <target-node> "grep \"$(date +%H:%M)\" /var/log/<service-name>/access.log | wc -l"
```

**Expected output:** Logs contain real requests (non-synthetic, non-health-check). Request count > 0 and growing.

#### Step 2: Monitor Health Checks (5-Minute Window)

```bash
ssh <monitoring-node> "/usr/local/bin/wheeler-health-watch \
  --service <service-name> \
  --target <target-node> \
  --duration 300 \
  --interval 10"
```

**Expected output:** `50/50 health checks passed` (30 checks over 5 minutes at 10s interval).

#### Step 3: Check Support/Error Reports

```bash
# Check incident channel, support ticket queue, and error tracking
ssh <monitoring-node> "/usr/local/bin/wheeler-check-incidents \
  --service <service-name> \
  --since '5 min ago'"
```

**Expected output:** `0 incidents reported for <service-name> since cutover`.

#### Step 4: Verify Old Service Is Still Running (Drained)

```bash
ssh <source-node> "pm2 status <service-name>"
ssh <source-node> "ss -tlnp | grep <service-port>"
```

**Expected output:** Old service `online` and port `LISTEN` (available for instant rollback). Access logs show no NEW connections (drained).

#### Step 5: Confirm Instant Revert Path

```bash
ssh <edge-node> "/opt/wheeler/rollback/<service-name>/quick-revert.sh --test"
```

**Expected output:** `QUICK REVERT: READY. Command: /opt/wheeler/rollback/<service-name>/quick-revert.sh` — execution time reported as < 10 seconds.

#### Step 6: Compare Error Rates

```bash
# Compare last 5 min error rate new vs. last hour average on old
ssh <monitoring-node> "/usr/local/bin/wheeler-compare-error-rate \
  --service <service-name> \
  --new-node <target-node> \
  --old-node <source-node> \
  --new-window 300 \
  --old-window 3600"
```

**Expected output:** `New error rate <= Old error rate` (within tolerance of ±10%).

#### Step 7: Compare Response Times

```bash
ssh <monitoring-node> "/usr/local/bin/wheeler-compare-latency \
  --service <service-name> \
  --new-node <target-node> \
  --old-node <source-node> \
  --percentile p95"
```

**Expected output:** `New p95 latency <= 1.2x Old p95 latency`.

### Pass/Fail Criteria

| Criteria | Threshold |
|---|---|
| Traffic flowing to new | Logs show real user requests |
| Health checks | 100% pass for >= 5 minutes |
| User-reported errors | 0 since cutover |
| Old service state | Running, drained, revert-ready |
| Quick revert test | Ready, < 10 seconds to execute |
| Error rate comparison | New <= Old (within 10%) |
| Latency comparison | New <= 1.2x Old |

### Required Artifacts

- [ ] Access log excerpt from new service (last 5 min)
- [ ] Health check timeline output (5-minute window)
- [ ] Incident/support ticket check output
- [ ] Error rate comparison output
- [ ] Latency comparison output

### Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **QA Lead** | | |
| **SRE Lead** | | |

### Rollback

```bash
# Instant revert: re-enable old route, drain new service
ssh <edge-node> "/opt/wheeler/rollback/<service-name>/quick-revert.sh"
```

This single command:
1. Re-points the proxy upstream to the old service
2. Reloads the proxy configuration
3. Drains the new service (stops accepting new connections)
4. Sends rollback notification via configured channel

### Automated Check Script

```
/usr/local/bin/wheeler-migrate gate8 --service <service-name> --source <source-node> --target <target-node>
```

---

## Gate 9 — 24-Hour Monitoring Passed

**Prerequisite:** Gate 8 passed.

### Why This Matters**

Real-world traffic patterns expose issues that synthetic tests miss: memory leaks under sustained load, connection pool exhaustion, cron-job spikes, cache eviction storms. One full business day of monitoring is the minimum observation period.

### Checklist

- [ ] **G9.1** — Zero unexpected restarts in the 24-hour observation window
- [ ] **G9.2** — Error rate remains at or below baseline (old service historical average)
- [ ] **G9.3** — p95 and p99 latency within SLA for all endpoints
- [ ] **G9.4** — Memory usage stable, no monotonic increase (no leak)
- [ ] **G9.5** — CPU usage stable, within expected range, no sustained spikes
- [ ] **G9.6** — All health checks green for the full 24-hour period (0 downtime events)
- [ ] **G9.7** — At least one scheduled backup completed successfully on target
- [ ] **G9.8** — Full log review completed with no unidentified anomalies
- [ ] **G9.9** — Old service stopped and decommissioned (after 24h confirmation)

### Verification Procedure

#### Step 1: Restart Count Check

```bash
# PM2
ssh <target-node> "pm2 list | grep <service-name> | awk '{print \"restarts: \" \$18}'"

# Docker
ssh <target-node> "docker inspect <container-name> --format '{{.RestartCount}}'"

# systemd
ssh <target-node> "journalctl -u <service-name> --since '24 hours ago' | grep -c 'Started'"
```

**Expected output:** Restart count = 0 (or exactly the number of intentional restarts documented in the migration runbook).

#### Step 2: Error Rate vs. Baseline

```bash
ssh <monitoring-node> "curl -s 'http://prometheus:9090/api/v1/query?query=sum(rate(http_requests_total{service=\"<service-name>\",status=~\"5..\"}[24h])) / sum(rate(http_requests_total{service=\"<service-name>\"}[24h])) * 100' | jq '.data.result[0].value[1]'"
```

Compare to baseline:
```bash
ssh <monitoring-node> "curl -s 'http://prometheus:9090/api/v1/query?query=avg_over_time(service_error_rate{service=\"<service-name>\"}[7d])' | jq '.data.result[0].value[1]'"
```

**Expected output:** 24h error rate <= 7-day baseline error rate (within 0.5 percentage points).

#### Step 3: Latency Check

```bash
# p95
ssh <monitoring-node> "curl -s 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service=\"<service-name>\"}[24h])) by (le))' | jq '.data.result[0].value[1]'"

# p99
ssh <monitoring-node> "curl -s 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service=\"<service-name>\"}[24h])) by (le))' | jq '.data.result[0].value[1]'"
```

**Expected output:** p95 and p99 within SLA thresholds defined for the service.

#### Step 4: Memory Stability

```bash
ssh <monitoring-node> "curl -s 'http://prometheus:9090/api/v1/query_range?query=process_resident_memory_bytes{service=\"<service-name>\"}&start=$(date -d '24 hours ago' +%s)&end=$(date +%s)&step=3600' | jq '.data.result[0].values | [.[][1] | tonumber] | {min: min, max: max, diff_pct: ((max - min) / min * 100)}'"
```

**Expected output:** Memory growth over 24 hours < 10% (if monotonically increasing, this indicates a potential leak — flag for investigation even if under 10%).

#### Step 5: CPU Stability

```bash
ssh <monitoring-node> "curl -s 'http://prometheus:9090/api/v1/query_range?query=rate(process_cpu_seconds_total{service=\"<service-name>\"}[5m])&start=$(date -d '24 hours ago' +%s)&end=$(date +%s)&step=3600' | jq '.data.result[0].values'"
```

**Expected output:** No sustained CPU spikes. Average CPU within expected operating range. No 100% utilization plateaus.

#### Step 6: Health Check Uptime

```bash
ssh <monitoring-node> "curl -s 'http://prometheus:9090/api/v1/query?query=avg_over_time(probe_success{service=\"<service-name>\"}[24h]) * 100' | jq '.data.result[0].value[1]'"
```

**Expected output:** `100.0` (100% uptime over 24 hours).

#### Step 7: Backup Verification on Target

```bash
ssh <target-node> "find /backups/<service-name>/ -type f -mtime -1 | wc -l"
ssh <target-node> "sha256sum -c /backups/<service-name>/checksums.sha256"
```

**Expected output:** At least one backup file < 24 hours old; checksums pass.

#### Step 8: Log Review

```bash
ssh <target-node> "/usr/local/bin/wheeler-log-review \
  --service <service-name> \
  --since '24 hours ago' \
  --output /var/log/wheeler/migrations/<service-name>/log-review.txt"
```

**Expected output:** Review notes indicate no unidentified anomalies. Any identified anomalies have been triaged and either resolved or documented as known/acceptable.

#### Step 9: Decommission Old Service

```bash
# ONLY after all G9.1-G9.8 pass
ssh <source-node> "pm2 stop <service-name> && pm2 delete <service-name>"
ssh <source-node> "rm -rf /opt/<service-name>/"  # Only if no shared artifacts remain
```

**Expected output:** Old service fully stopped and removed. Resources freed on source node.

### Pass/Fail Criteria

| Criteria | Threshold |
|---|---|
| Restarts | 0 unexpected (intentional documented OK) |
| Error rate | <= 7-day baseline |
| p95 latency | Within SLA |
| p99 latency | Within SLA |
| Memory stability | Growth < 10% over 24h, no monotonic leak |
| CPU stability | No sustained spikes, within expected range |
| Health uptime | 100% over 24h |
| Backup on target | At least 1 successful |
| Log review | No unidentified anomalies |
| Old service | Decommissioned |

### Required Artifacts

- [ ] 24-hour Grafana dashboard screenshot (showing all panels)
- [ ] Prometheus metrics summary (RESTARTS, ERROR_RATE, P95, P99, MEMORY, CPU, UPTIME)
- [ ] Log review notes
- [ ] Old service decommission confirmation

### Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **SRE Lead** | | |
| **Engineering Manager** | | |

### Rollback

> **Full rollback to old service.** If any Gate 9 criterion fails after 24 hours:

1. Execute full rollback: `/opt/wheeler/rollback/<service-name>/rollback.sh --full`
2. Restore old service from most recent backup if needed
3. Schedule a **post-mortem meeting** within 48 hours
4. Document all findings in the Migration Accountability Record before any re-attempt

### Automated Check Script

```
/usr/local/bin/wheeler-migrate gate9 --service <service-name> --target <target-node>
```

---

## Migration Gate Summary Matrix

| Service | Gate 1<br>Source Health | Gate 2<br>Backup | Gate 3<br>Target Start | Gate 4<br>Target Health | Gate 5<br>Dependencies | Gate 6<br>Public Route | Gate 7<br>Rollback | Gate 8<br>Cutover | Gate 9<br>24h Monitor | Overall |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Service A** | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | **PENDING** |
| **Service B** | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | **PENDING** |
| **Service C** | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | **PENDING** |
| **Service D** | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | **PENDING** |
| **Service E** | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | **PENDING** |
| **Service F** | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | **PENDING** |
| **Service G** | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | **PENDING** |
| **Service H** | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | **PENDING** |
| **Service I** | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | **PENDING** |

> **Instructions:** Add each service to the matrix before its first migration. Mark [x] as each gate passes. The Final Migration Approval requires all 9 gates checked for the service being migrated.

### Gate-to-Service Mapping Quick Reference

For each service, document:
- **Source Node:** (EDGE / AIOPS / COREDB)
- **Target Node:** (EDGE / AIOPS / COREDB)
- **Migration Owner:** (name)
- **Scheduled Window:** (date + time range in UTC)
- **Risk Level:** (LOW / MEDIUM / HIGH / CRITICAL)

| Service | Source | Target | Owner | Window | Risk | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |
| | | | | | | |
| | | | | | | |

---

## Emergency Migration Override Procedure

> **WARNING:** This procedure exists for genuine emergencies only. Abuse of the override process will result in a mandatory Migration Readiness Audit and potential revocation of deployment privileges.

### When an Override Is Permitted

| Scenario | Category | Authorizer |
|---|---|---|
| Active security incident (CVE with CVSS >= 9.0, active exploitation) | **SECURITY** | CISO or Security Lead |
| Critical outage with revenue impact (P0 incident > 30 minutes) | **OUTAGE** | VP Engineering or CTO |
| Data loss in progress (corruption spreading, replication failing) | **DATA** | VP Engineering + DBA Lead |
| Compliance deadline (< 4 hours to regulatory deadline) | **COMPLIANCE** | CTO + Legal |
| Infrastructure degradation (node hardware failure imminent) | **INFRA** | SRE Lead + Engineering Manager |

### Gates That CAN Be Overridden (and Conditions)

| Gate | Security | Outage | Data | Compliance | Infra |
|---|---|---|---|---|---|
| Gate 1 (Source Health) | WAIVABLE* | WAIVABLE* | NO | NO | WAIVABLE* |
| Gate 2 (Backup) | NO | WAIVABLE** | NO | NO | WAIVABLE** |
| Gate 3 (Target Start) | NO | NO | NO | NO | NO |
| Gate 4 (Target Health) | WAIVABLE* | WAIVABLE* | NO | WAIVABLE* | WAIVABLE* |
| Gate 5 (Dependencies) | WAIVABLE* | WAIVABLE* | NO | WAIVABLE* | WAIVABLE* |
| Gate 6 (Public Route) | NO | NO | NO | NO | NO |
| Gate 7 (Rollback) | NO | NO | NO | NO | NO |
| Gate 8 (Cutover) | WAIVABLE* | WAIVABLE* | NO | NO | WAIVABLE* |
| Gate 9 (24h Monitor) | NO | NO | NO | NO | NO |

- **NO** = Cannot be overridden under any circumstances
- **WAIVABLE\*** = Can be overridden with documented justification and post-migration remediation plan (must be completed within 48 hours)
- **WAIVABLE\*\*** = Can be overridden only if a backup from within the last 7 days exists and passes integrity check

### Override Procedure

1. **Declare emergency:** Notify #incident-response channel with `!migration-override <service-name> <emergency-category>`
2. **Obtain authorization:** At least one authorizer from the category column above must approve in writing (Slack message or signed ticket)
3. **Document override:** Fill out the Emergency Override Record (see below)
4. **File override:** Save to `/var/log/wheeler/migrations/<service-name>/overrides/<YYYY-MM-DD>-override.json`
5. **Execute migration:** Proceed with waived gates
6. **Post-migration:** Complete all waived gate requirements within 48 hours. Failure to remediate within 48 hours triggers automatic rollback.

### Emergency Override Record

```json
{
  "migration_id": "MIG-<service-name>-<YYYYMMDD>-<HHMM>",
  "emergency_category": "SECURITY|OUTAGE|DATA|COMPLIANCE|INFRA",
  "authorized_by": {
    "name": "",
    "role": "",
    "timestamp": ""
  },
  "waived_gates": [1, 2, 4],
  "justification": "",
  "incident_ticket": "",
  "remediation_deadline": "",
  "remediation_completed": false,
  "remediation_ticket": ""
}
```

### Override Audit Trail

All overrides are reviewed at the weekly Operations Review meeting. Patterns of override usage trigger a **Root Cause Analysis** and potential revision of the migration runbook.

---

## Post-Migration Validation Checklist

After Gate 9 passes and the old service is decommissioned, complete the following within 72 hours:

- [ ] **PV.1** — All monitoring dashboards updated to point at new service metrics
- [ ] **PV.2** — Alerting rules updated with new node and service identifiers
- [ ] **PV.3** — Backup schedule confirmed running on target (at least 2 successful cycles)
- [ ] **PV.4** — Documentation updated: runbooks, architecture diagrams, service catalog
- [ ] **PV.5** — Source node resources freed and verified (disk space reclaimed, ports released)
- [ ] **PV.6** — Migration Accountability Record finalized and archived
- [ ] **PV.7** — Retrospective meeting scheduled (within 5 business days)
- [ ] **PV.8** — Lessons learned captured in migration playbook
- [ ] **PV.9** — Stakeholder communication sent (migration completion notice)
- [ ] **PV.10** — Any waived gate remediation confirmed complete

### PV Sign-off

| Role | Name | Signature/Date |
|---|---|---|
| **SRE Lead** | | |
| **Engineering Manager** | | |
| **Product Owner** | | |

---

## Migration Log Template

Each migration MUST maintain a chronological log. Use this template:

```markdown
# Migration Log — <SERVICE NAME>

| Field | Value |
|---|---|
| **Migration ID** | MIG-<service>-<YYYYMMDD>-<HHMM> |
| **Service** | |
| **Source Node** | |
| **Target Node** | |
| **Migration Owner** | |
| **Scheduled Window (UTC)** | |
| **Actual Start (UTC)** | |
| **Actual End (UTC)** | |
| **Risk Level** | LOW / MEDIUM / HIGH / CRITICAL |
| **Final Status** | SUCCESS / PARTIAL / ROLLED BACK / FAILED |

---

## Chronological Log

### [YYYY-MM-DD HH:MM UTC] Gate 1 — Source Service Healthy
- **Result:** PASS / FAIL
- **Duration:** X minutes
- **Notes:**
- **Artifact Path:** /var/log/wheeler/migrations/<service>/<date>/gate-1/

### [YYYY-MM-DD HH:MM UTC] Gate 2 — Backup Exists
- **Result:** PASS / FAIL
- **Duration:** X minutes
- **Notes:**
- **Artifact Path:** /var/log/wheeler/migrations/<service>/<date>/gate-2/

### [YYYY-MM-DD HH:MM UTC] Gate 3 — Target Service Starts
- **Result:** PASS / FAIL
- **Duration:** X minutes
- **Notes:**
- **Artifact Path:** /var/log/wheeler/migrations/<service>/<date>/gate-3/

### [YYYY-MM-DD HH:MM UTC] Gate 4 — Target Health Passes
- **Result:** PASS / FAIL
- **Duration:** X minutes
- **Notes:**
- **Artifact Path:** /var/log/wheeler/migrations/<service>/<date>/gate-4/

### [YYYY-MM-DD HH:MM UTC] Gate 5 — Dependency Tests Pass
- **Result:** PASS / FAIL
- **Duration:** X minutes
- **Notes:**
- **Artifact Path:** /var/log/wheeler/migrations/<service>/<date>/gate-5/

### [YYYY-MM-DD HH:MM UTC] Gate 6 — Public Route Can Switch
- **Result:** PASS / FAIL
- **Duration:** X minutes
- **Notes:**
- **Artifact Path:** /var/log/wheeler/migrations/<service>/<date>/gate-6/

### [YYYY-MM-DD HH:MM UTC] Gate 7 — Rollback Command Exists
- **Result:** PASS / FAIL
- **Duration:** X minutes
- **Notes:**
- **Artifact Path:** /var/log/wheeler/migrations/<service>/<date>/gate-7/

### [YYYY-MM-DD HH:MM UTC] Gate 8 — Old Service Stopped After New Verified
- **Result:** PASS / FAIL
- **Duration:** X minutes
- **Notes:**
- **Artifact Path:** /var/log/wheeler/migrations/<service>/<date>/gate-8/

### [YYYY-MM-DD HH:MM UTC] Gate 9 — 24-Hour Monitoring Passed
- **Result:** PASS / FAIL
- **Duration:** 24 hours (observation window)
- **Notes:**
- **Artifact Path:** /var/log/wheeler/migrations/<service>/<date>/gate-9/

---

## Approval Signatures

| Gate | Role | Name | Signed (date/time) | Status |
|---|---|---|---|---|
| 1 | QA Engineer | | | |
| 2 | SRE | | | |
| 3 | SRE | | | |
| 4 | QA Engineer | | | |
| 5 | SRE + QA Engineer | | | |
| 6 | SRE + Network Engineer | | | |
| 7 | SRE Lead | | | |
| 8 | QA Lead + SRE Lead | | | |
| 9 | SRE Lead + Engineering Manager | | | |

---

## Incident Log

| Time (UTC) | Severity | Description | Resolution | Gate Impact |
|---|---|---|---|---|
| | | | | |
| | | | | |

---

## Post-Mortem Summary

*(Complete only if migration resulted in an incident)*

- **What went well:**
- **What went wrong:**
- **Root cause:**
- **Impact (duration, users affected):**
- **Action items:**
  1.
  2.
  3.
```

---

## Appendix A: Automated Validation Script Index

| Script | Gates Covered | Location |
|---|---|---|
| `wheeler-migrate` | All gates (1-9) | `/usr/local/bin/wheeler-migrate` |
| `wheeler-check-deps` | Gate 1, Gate 5 | `/usr/local/bin/wheeler-check-deps` |
| `wheeler-check-ports` | Gate 3 | `/usr/local/bin/wheeler-check-ports` |
| `wheeler-log-scan` | Gate 4 | `/usr/local/bin/wheeler-log-scan` |
| `wheeler-log-review` | Gate 9 | `/usr/local/bin/wheeler-log-review` |
| `wheeler-health-watch` | Gate 8 | `/usr/local/bin/wheeler-health-watch` |
| `wheeler-check-incidents` | Gate 8 | `/usr/local/bin/wheeler-check-incidents` |
| `wheeler-compare-error-rate` | Gate 8 | `/usr/local/bin/wheeler-compare-error-rate` |
| `wheeler-compare-latency` | Gate 8 | `/usr/local/bin/wheeler-compare-latency` |
| `wheeler-verify-consistency` | Gate 7 | `/usr/local/bin/wheeler-verify-consistency` |
| `wheeler-export-env` | Gate 2 | `/usr/local/bin/wheeler-export-env` |
| `wheeler-restore-test` | Gate 2 | `/usr/local/bin/wheeler-restore-test` |
| `wheeler-check-lb-pool` | Gate 6 | `/usr/local/bin/wheeler-check-lb-pool` |

## Appendix B: Artifact Storage Convention

```
/var/log/wheeler/migrations/
  <service-name>/
    <YYYY-MM-DD>/
      migration-log.md
      gate-1/
        health-check.txt
        pm2-status.txt
        dependency-test.txt
        port-check.txt
      gate-2/
        backup-paths.txt
        checksums.sha256
        env-export.json
        restore-test.txt
      gate-3/
        start-command.txt
        port-check.txt
        process-list.txt
        firewall-rules.txt
      gate-4/
        health-curl.txt
        log-excerpt.txt
        timing-data.txt
        memory-comparison.txt
      gate-5/
        db-connect.txt
        redis-connect.txt
        api-reachable.txt
        storage-test.txt
        dns-resolution.txt
      gate-6/
        dns-dig.txt
        cf-config.json
        proxy-diff.txt
        ssl-dates.txt
        dry-run-traffic.txt
      gate-7/
        rollback-script-path.txt
        staging-test.txt
        consistency-check.txt
        notification-template.md
      gate-8/
        access-log-excerpt.txt
        health-timeline.txt
        incident-check.txt
        error-rate-comparison.txt
        latency-comparison.txt
      gate-9/
        grafana-dashboard.png
        prometheus-summary.json
        log-review.txt
        decommission-confirmation.txt
      overrides/
        <YYYY-MM-DD>-override.json
```

## Appendix C: Glossary

| Term | Definition |
|---|---|
| **MAR** | Migration Accountability Record — the master document tracking a migration from Gate 1 through post-migration |
| **Soft Cutover** | The period in Gate 8 where old and new services run simultaneously, with traffic flowing to the new service but old service kept alive for instant rollback |
| **Drained** | A service state where existing connections are allowed to complete but no new connections are accepted |
| **Quick Revert** | The single-command rollback path validated in Gate 8, designed to execute in under 10 seconds |
| **SLA** | Service Level Agreement — per-service performance and availability targets defined in the Wheeler SLA Register |
| **P0 Incident** | A Priority 0 incident: complete service outage with direct revenue impact |

---

> **Document Control:** This document is reviewed quarterly by the Production Readiness Board. Any deviations or proposed changes must be submitted as a PR to the `wheeler-docs` repository with the `migration-gate` label.

| Version | Date | Author | Changes |
|---|---|---|---|
| v1.0 | 2026-05-23 | Principal Production Readiness Auditor | Initial release |
