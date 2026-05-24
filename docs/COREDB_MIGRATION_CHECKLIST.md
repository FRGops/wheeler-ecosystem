# COREDB Migration Checklist: CPX51 to CX31

**Server**: wheeler-core-db-01 (5.78.210.123)
**Plan**: Hetzner CPX51 (16 vCPU, 30 GB, 360 GB) to CX31 (8 vCPU, 16 GB, 160 GB)
**Estimated total downtime**: 25-40 minutes
**Date prepared**: 2026-05-23

---

## Phase 0 -- Pre-Flight Verification (Run BEFORE shutdown)

### 0.1 Verify current server is healthy

```bash
ssh root@5.78.210.123 "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

All 18 containers should show "Up". If any are restarting or down, investigate before proceeding.

### 0.2 Take a fresh PostgreSQL backup

```bash
ssh root@5.78.210.123 "/opt/backups/backup-postgres.sh"
```

Tail the log to confirm success:
```bash
ssh root@5.78.210.123 "tail -20 /var/log/postgres-backup.log"
```

Expected output: "Success: X  Failed: 0" for databases wheeler_core, usesend, temporal, temporal_db, temporal_visibility.

### 0.3 Copy backups and Docker volumes off-server

This is your rollback safety net. Run from your local machine:

```bash
# Pull the latest backups
rsync -avz --progress root@5.78.210.123:/opt/backups/databases/ /tmp/coredb-backups-$(date +%Y%m%d)/

# Pull the Docker volumes (570 MB total)
ssh root@5.78.210.123 "tar -czf /tmp/docker-volumes.tar.gz -C /var/lib/docker/volumes ."
scp root@5.78.210.123:/tmp/docker-volumes.tar.gz /tmp/docker-volumes-$(date +%Y%m%d).tar.gz
ssh root@5.78.210.123 "rm /tmp/docker-volumes.tar.gz"
```

### 0.4 Record critical state

```bash
# Capture UFW rules (will recreate on target)
ssh root@5.78.210.123 "ufw status verbose" > /tmp/coredb-ufw-rules.txt

# Capture Docker networks
ssh root@5.78.210.123 "docker network ls -q | xargs -I{} docker network inspect {}" > /tmp/coredb-networks.json

# Capture the crontab entry
ssh root@5.78.210.123 "crontab -l" > /tmp/coredb-crontab.txt

# Capture Tailscale node list
ssh root@5.78.210.123 "tailscale status" > /tmp/coredb-tailscale.txt
```

### 0.5 Prepare Hetzner Cloud credentials

Ensure you have:
- `hcloud` CLI installed and authenticated (`hcloud context list` -- should show active token)
- Or access to the Hetzner Cloud Console at https://console.hetzner.cloud

### 0.6 Record the SSH key name

```bash
hcloud ssh-key list
```

Note the name(s) of the SSH key(s) attached to the current server. You will need the same key(s) on the new server. Find the current keys:

```bash
hcloud server describe wheeler-core-db-01 -o json | jq '.ssh_keys[].name'
```

---

## Phase 1 -- Shutdown Sequence (5 minutes)

Execute all commands via SSH to 5.78.210.123.

### 1.1 Stop application containers first (depends on core services)

```bash
ssh root@5.78.210.123 << 'EOF'
cd /opt/apps/prediction-radar && docker compose down
cd /opt/apps/temporal-pipeline && docker compose down
cd /opt/apps/usesend && docker compose down
EOF
```

### 1.2 Stop Temporal (depends on PostgreSQL)

```bash
ssh root@5.78.210.123 "cd /opt/temporal && docker compose down"
```

### 1.3 Stop monitoring stack

```bash
ssh root@5.78.210.123 "cd /opt/wheeler-monitoring && docker compose down"
```

### 1.4 Stop core services LAST (PostgreSQL, Redis, MinIO)

```bash
ssh root@5.78.210.123 "cd /opt/wheeler-core && docker compose down"
```

### 1.5 Verify everything is stopped

```bash
ssh root@5.78.210.123 "docker ps -a"
```

All containers should show "Exited" status. No containers should be running.

### 1.6 Stop Docker daemon (paranoid safety for snapshot)

```bash
ssh root@5.78.210.123 "systemctl stop docker"
```

The server is now in a clean, stopped state.

---

## Phase 2 -- Snapshot and Server Creation (10-15 minutes)

### Option A: Hetzner Cloud Console (GUI -- recommended for safety)

1. Log into https://console.hetzner.cloud
2. Navigate to the server `wheeler-core-db-01` (IP 5.78.210.123)
3. **Power off** the server from the console
4. Go to **Snapshots** tab, click **Create Snapshot**
   - Name: `wheeler-core-db-01-migration-20260523`
   - Wait for snapshot to complete (indicator turns green, typically 2-5 min)
5. Note the **Snapshot ID** from the URL or snapshot list
6. Go to **Servers** > **Add Server**
7. Choose:
   - **Location**: Hillsboro, OR (us-west)
   - **Image**: **Snapshot** tab, select `wheeler-core-db-01-migration-20260523`
   - **Type**: **CX31** (8 vCPU, 16 GB RAM, 160 GB disk)
   - **Networking**: Public IPv4 (will be auto-assigned, different from old IP)
   - **SSH Keys**: Attach the same SSH key(s) from Phase 0.6
   - **Name**: `wheeler-core-db-01` (keeps the same hostname convention)
8. Click **Create & Buy Now**
9. Wait for server to provision (green status, ~2 min)
10. Note the **NEW IP ADDRESS** from the server detail page

### Option B: hcloud CLI

```bash
# 1. Power off the server (if not already off)
hcloud server poweroff wheeler-core-db-01

# 2. Create snapshot (wait until it completes)
hcloud server create-image wheeler-core-db-01 \
  --description "Migration snapshot before CPX51->CX31 right-size" \
  --type snapshot

# List images to get the ID
hcloud image list --type snapshot --sort created:desc | head -5
# Note: SNAPSHOT_ID is the numeric ID, e.g., 12345678

# 3. Create new CX31 server from snapshot
hcloud server create \
  --name wheeler-core-db-01 \
  --type cx31 \
  --location hillsboro \
  --image <SNAPSHOT_ID> \
  --ssh-key <SSH_KEY_NAME>

# 4. Get the new IP
hcloud server describe wheeler-core-db-01 -o json | jq '.public_net.ipv4.ip'
```

### 2.1 Cleanup old CPX51 server

After confirming the new server boots and is accessible via SSH, delete the old one:

```bash
hcloud server delete wheeler-core-db-01-old
# Or rename old first:
# hcloud server rename wheeler-core-db-01 wheeler-core-db-01-old
# Then rename new to wheeler-core-db-01
```

**Note regarding naming**: Since the old and new servers should not share the same name in Hetzner Cloud, you may need to:
1. Rename old: `hcloud server rename wheeler-core-db-01 wheeler-core-db-01-old`
2. Create new with name `wheeler-core-db-01`
3. Delete old after verification

---

## Phase 3 -- Post-Migration Startup (10-15 minutes)

SSH to the **new IP** (let's call it `<NEW_IP>`) for all commands below.

### 3.1 First SSH and verify system booted

```bash
ssh root@<NEW_IP> "uptime; hostnamectl; df -h /"
```

Expected: Ubuntu 26.04, hostname "wheeler-core-db-01", disk ~160 GB.

### 3.2 Verify Docker volumes survived snapshot

```bash
ssh root@<NEW_IP> "docker volume ls"
```

Expected: the same 7 volumes (wheeler-core_postgres_data, wheeler-core_redis_data, wheeler-core_minio_data, wheeler-monitoring_grafana_data, wheeler-monitoring_loki_data, wheeler-monitoring_prometheus_data, wheeler-monitoring_uptime_kuma_data).

### 3.3 Start Docker daemon if not running

```bash
ssh root@<NEW_IP> "systemctl start docker && systemctl enable docker"
```

### 3.4 Recreate Docker networks (they may have been lost)

```bash
ssh root@<NEW_IP> << 'EOF'
docker network create --driver bridge wheeler-core_default
docker network create --driver bridge wheeler-monitoring_default
EOF
```

If the snapshot preserved them, these commands will fail harmlessly with "network already exists."

### 3.5 Start core services FIRST (PostgreSQL, Redis, MinIO)

```bash
ssh root@<NEW_IP> "cd /opt/wheeler-core && docker compose up -d"
```

Wait for PostgreSQL to be ready:
```bash
ssh root@<NEW_IP> "until docker exec wheeler-postgres pg_isready -U wheeler; do echo 'Waiting for PostgreSQL...'; sleep 2; done"
```

### 3.6 Start Temporal (depends on PostgreSQL)

```bash
ssh root@<NEW_IP> "cd /opt/temporal && docker compose up -d"
```

Wait for Temporal to be healthy:
```bash
ssh root@<NEW_IP> "until curl -s http://localhost:7233/health 2>/dev/null; do echo 'Waiting for Temporal...'; sleep 2; done"
```

### 3.7 Start monitoring stack

```bash
ssh root@<NEW_IP> "cd /opt/wheeler-monitoring && docker compose up -d"
```

### 3.8 Start application stacks

```bash
ssh root@<NEW_IP> << 'EOF'
cd /opt/apps/prediction-radar && docker compose up -d
cd /opt/apps/temporal-pipeline && docker compose up -d
cd /opt/apps/usesend && docker compose up -d
EOF
```

### 3.9 Restore the cron job

```bash
ssh root@<NEW_IP> "(crontab -l 2>/dev/null; echo '0 3 * * * /opt/backups/backup-postgres.sh >> /var/log/postgres-backup.log 2>&1') | crontab -"
```

Verify:
```bash
ssh root@<NEW_IP> "crontab -l"
```

### 3.10 Reconfigure UFW firewall

The snapshot should preserve UFW rules, but the new IP may affect the Tailscale interface name. Verify:

```bash
ssh root@<NEW_IP> "ufw status verbose"
```

If rules are missing, re-apply from the saved file:
```bash
# Review the saved rules first
cat /tmp/coredb-ufw-rules.txt

# Recreate critical rules (execute on the new server):
ssh root@<NEW_IP> << 'EOF'
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow in on tailscale0 to any port 5432 proto tcp
ufw allow in on tailscale0 to any port 6379 proto tcp
ufw allow in on tailscale0 to any port 9000 proto tcp
ufw allow in on tailscale0 to any port 3000 proto tcp
ufw allow from 127.0.0.1 to any port 5432 proto tcp
ufw allow from 127.0.0.1 to any port 6379 proto tcp
ufw allow from 127.0.0.1 to any port 9000 proto tcp
ufw allow from 127.0.0.1 to any port 3000 proto tcp
ufw allow 3001/tcp   # Uptime Kuma (public)
ufw deny 3000/tcp     # Grafana (public blocked)
ufw deny 9000/tcp     # MinIO API (public blocked)
ufw deny 9001/tcp     # MinIO Console (public blocked)
ufw deny 9090/tcp     # Prometheus (public blocked)
ufw deny 3100/tcp     # Loki (public blocked)
ufw deny 5432/tcp     # PostgreSQL (public blocked)
ufw deny 6379/tcp     # Redis (public blocked)
ufw --force enable
ufw status verbose
EOF
```

---

## Phase 4 -- Verification (5-10 minutes)

Run ALL checks from your local machine against the new IP.

### 4.1 Container health check

```bash
ssh root@<NEW_IP> "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

All 18 containers must show "Up":
- wheeler-postgres
- wheeler-redis
- wheeler-minio
- temporal-server
- temporal-ui
- wheeler-grafana
- wheeler-prometheus
- wheeler-loki
- wheeler-uptime-kuma
- node-exporter
- postgres-exporter
- redis-exporter
- promtail
- prediction-radar-worker
- prediction-radar-scheduler
- temporal-pipeline-worker
- temporal-pipeline-scheduler
- usesend

### 4.2 PostgreSQL connectivity

```bash
ssh root@<NEW_IP> "docker exec wheeler-postgres psql -U wheeler -d wheeler_core -c 'SELECT version();'"
```

Should return PostgreSQL version string and no connection errors. Then verify databases exist:

```bash
ssh root@<NEW_IP> "docker exec wheeler-postgres psql -U wheeler -d wheeler_core -c '\l'"
```

Expected databases: wheeler_core, usesend, temporal, temporal_db, temporal_visibility, prediction_radar.

### 4.3 Temporal UI

```bash
curl -s -o /dev/null -w "%{http_code}" http://<NEW_IP>:8080
```

Should return HTTP 200. Also open in browser: `http://<NEW_IP>:8080`

### 4.4 MinIO

```bash
curl -s -o /dev/null -w "%{http_code}" http://<NEW_IP>:9000
```

Should return HTTP 403 (expected -- MinIO returns 403 for unauthenticated API requests, which confirms it is running). Console at `http://<NEW_IP>:9001` should load in a browser.

### 4.5 Grafana

```bash
curl -s -o /dev/null -w "%{http_code}" http://<NEW_IP>:3000
```

Should return HTTP 302 (redirect to login) or 200.

### 4.6 Tailscale connectivity

```bash
ssh root@<NEW_IP> "tailscale status"
```

Should show the node online with its new tailnet IP. Verify that wheeler-aiops-01 (100.121.230.28) is listed and reachable:

```bash
ssh root@<NEW_IP> "ping -c 2 -W 3 100.121.230.28"
```

### 4.7 Backup script test

```bash
ssh root@<NEW_IP> "/opt/backups/backup-postgres.sh && tail -10 /var/log/postgres-backup.log"
```

Confirm "Success: X  Failed: 0".

### 4.8 Application smoke tests

```bash
# Usesend (port 3007)
curl -s -o /dev/null -w "%{http_code}" http://<NEW_IP>:3007

# Uptime Kuma (port 3001)
curl -s -o /dev/null -w "%{http_code}" http://<NEW_IP>:3001

# Temporal gRPC endpoint
ssh root@<NEW_IP> "docker exec temporal-server tctl cluster health"
```

### 4.9 Resource utilization

```bash
ssh root@<NEW_IP> "free -h; echo '---'; docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'"
```

---

## Phase 5 -- Update References (As Needed)

### 5.1 IP-dependent files found on old server

The following files contain `5.78.210.123`. These are all documentation/inventory files -- none are active configuration. Review and update if they contain IP references you need to keep current:

| File | Action |
|------|--------|
| `/opt/wheeler-security-audit/inventory/port-exposure-wheeler-core-db-01-*.txt` | No action (historical audit) |
| `/opt/wheeler-security-audit/inventory/CONSOLIDATED_FINDINGS.md` | No action (historical) |
| `/opt/wheeler-security-audit/scripts/port-exposure-audit.sh` | No action (reusable script) |
| `/opt/wheeler-security-audit/docs/*.md` | No action (historical docs) |
| `/root/postgres-optimizations/optimized-wheeler-postgres.conf` | No action (config, IP is only in SSH example comments) |
| `/root/postgres-optimizations/safe-apply-postgres-tuning.sh` | No action (script, IP only in connection examples) |

**Key finding**: No active configuration files (docker-compose, .env, .conf, .json) hardcode the public IP. All inter-service communication uses Docker internal DNS (e.g., `wheeler-postgres:5432`) or Tailscale IPs (e.g., `100.121.230.28`).

### 5.2 Tailscale IP change

After the migration, the Tailscale node for wheeler-core-db-01 will have a new Tailscale IP (it was `100.118.166.117`). Check if any other services reference this IP:

```bash
# On wheeler-aiops-01 or other Tailscale nodes
grep -r "100.118.166.117" /opt/ /etc/ 2>/dev/null
```

The Tailscale hostname (`wheeler-core-db-01`) stays the same, so DNS-based references should auto-resolve. If any service hardcodes the Tailscale IP, update it.

### 5.3 Update your local SSH config and known_hosts

```bash
# Remove old host key
ssh-keygen -R 5.78.210.123

# Add new host entry to ~/.ssh/config if you have one
# Replace any reference to 5.78.210.123 with <NEW_IP>
```

---

## Phase 6 -- Rollback Procedure (If Needed)

If the new server has issues, roll back to the old CPX51:

### 6.1 Power on the old server

```bash
hcloud server poweron wheeler-core-db-01-old
```

### 6.2 SSH and start Docker

```bash
ssh root@5.78.210.123 "systemctl start docker"
```

### 6.3 Start all stacks (reverse of shutdown)

```bash
ssh root@5.78.210.123 << 'EOF'
cd /opt/wheeler-core && docker compose up -d
sleep 10
cd /opt/temporal && docker compose up -d
cd /opt/wheeler-monitoring && docker compose up -d
cd /opt/apps/prediction-radar && docker compose up -d
cd /opt/apps/temporal-pipeline && docker compose up -d
cd /opt/apps/usesend && docker compose up -d
EOF
```

### 6.4 Run Phase 4 verification against 5.78.210.123

### 6.5 If the old server is unrecoverable

Restore from the backups pulled in Phase 0.3:
1. Create a fresh CX31 or CPX51 server
2. SCP the volume tarball and database dumps to it
3. Extract volumes to `/var/lib/docker/volumes/`
4. Recreate Docker networks
5. Start all compose stacks
6. If volumes didn't restore cleanly, use `pg_restore` to reload from the `.dump.gz` files

---

## Timing Summary

| Phase | Description | Estimated Time |
|-------|-------------|----------------|
| 0 | Pre-flight verification and off-server backup | 5-10 min (offline prep) |
| 1 | Shutdown sequence | 5 min |
| 2 | Snapshot and server creation | 10-15 min |
| 3 | Startup sequence | 10-15 min |
| 4 | Verification | 5-10 min |
| 5 | Reference updates | 5 min (post-migration) |
| **Total downtime** | **25-40 min** | |

---

## Quick Reference: Key Ports

| Port | Service | Public Access |
|------|---------|---------------|
| 22 | SSH | Allowed |
| 3001 | Uptime Kuma | Allowed |
| 5432 | PostgreSQL | Tailscale + localhost only |
| 6379 | Redis | Tailscale + localhost only |
| 8080 | Temporal UI | Open |
| 7233 | Temporal gRPC | Open |
| 3000 | Grafana | Tailscale + localhost only |
| 9000 | MinIO API | Tailscale + localhost only |
| 9001 | MinIO Console | Blocked publicly |
| 9090 | Prometheus | Blocked publicly |
| 3100 | Loki | Blocked publicly |

---

## Go/No-Go Checklist (Complete Before Starting)

- [ ] Fresh PostgreSQL backup completed successfully
- [ ] Docker volumes copied off-server
- [ ] UFW rules captured
- [ ] Crontab captured
- [ ] Hetzner Cloud access confirmed (console or hcloud CLI)
- [ ] SSH key name(s) identified
- [ ] Maintenance window confirmed (20-40 minutes)
- [ ] Stakeholders notified of downtime window
- [ ] Rollback path understood by operator
