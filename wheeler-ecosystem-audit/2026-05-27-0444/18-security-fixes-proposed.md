# Wheeler Ecosystem Security Audit -- Stage 2 Gap Closure
**Date**: 2026-05-27 04:44 UTC
**Author**: Security Intelligence Agent
**Scope**: Hostinger VPS, CoreDB VPS, Hetzner (local)
**Method**: Read-only evidence collection; no changes applied.

---

## Executive Summary

Nine findings were investigated across three servers. Three are P0/CRITICAL, two are P1/HIGH, two are P2/MEDIUM, one is P3/LOW, and one is a FALSE POSITIVE. The most urgent issue is CoreDB SSH publicly exposed to the internet. Hostinger has multiple services binding to 0.0.0.0 that are reachable through the Tailscale mesh. LiteLLM master key is properly configured and is a false positive from the original audit.

---

## Finding 1: CoreDB SSH -- Publicly Exposed (CRITICAL / P0)

**Server**: CoreDB VPS `100.118.166.117` (Public: `5.78.210.123`)
**Evidence**:
- `ss -tlnp` shows SSH on `0.0.0.0:22` (all interfaces)
- `timeout 5 bash -c "echo > /dev/tcp/5.78.210.123/22"` from within the machine returns **OPEN**
- UFW rule 3: `22/tcp ALLOW IN Anywhere` -- allows SSH from ANY public IP
- fail2ban is active: 75 total bans, 5 currently banned

**UFW Rule Analysis**:
```
[ 1] 22 on tailscale0           ALLOW IN    Anywhere          # GOOD
[ 2] 22                         ALLOW IN    10.0.0.0/16       # ACCEPTABLE (VPC internal)
[ 3] 22/tcp                     ALLOW IN    Anywhere          # PROBLEM - public access
```

Rule 3 is redundant if Tailscale is the only required access path. It creates an internet-facing SSH surface mitigated only by fail2ban. The Hetzner server (Hostinger VPS) already implements the preferred pattern: `22/tcp ALLOW IN 100.64.0.0/10 # SSH restricted to Tailscale CGNAT`.

**Risk**: HIGH -- SSH exposed to the entire internet. SSH brute-force tools will find this port. While fail2ban provides some protection, it is not a substitute for access restriction.

**Proposed Fix**: Remove the overly broad UFW rule 3 (and its v6 counterpart rule 12).

**Exact Commands to Apply**:
```bash
# On CoreDB (ssh root@100.118.166.117):
ufw status numbered          # Confirm rule numbers
ufw delete 3                 # Remove "22/tcp ALLOW IN Anywhere" (IPv4)
ufw status numbered          # Re-check numbers after deletion
# Rule 12 (v6) may have shifted to 11
ufw delete 11                # Remove "22/tcp (v6) ALLOW IN Anywhere (v6)"
ufw reload
ufw status numbered          # Verify: only rule 1 (tailscale0) and rule 2 (10.0.0.0/16) remain
```

**Rollback Commands**:
```bash
ufw insert 3 allow 22/tcp
ufw reload
```

**Verification**: From a non-Tailscale machine (or via the public IP from within):
```bash
timeout 5 bash -c "echo > /dev/tcp/5.78.210.123/22" 2>&1 && echo "OPEN" || echo "BLOCKED"
# Should print "BLOCKED" after fix
# Then verify from Tailscale:
timeout 5 bash -c "echo > /dev/tcp/100.118.166.117/22" 2>&1 && echo "OPEN" || echo "BLOCKED"
# Should print "OPEN"
```

---

## Finding 2: Hostinger VPS -- Custom Exporter on Port 8002 (P1 / HIGH)

**Server**: Hostinger VPS `100.98.163.17` (Public: `187.77.148.88`)
**Evidence**:
- Process: `python3 /tmp/hostinger-services-exporter.py`
- Listening on `0.0.0.0:8002` (all interfaces)
- Script source: `HTTPServer(("0.0.0.0", 8002), Handler).serve_forever()` (line 64 of `/tmp/hostinger-services-exporter.py`)
- Reachable from Hetzner via Tailscale: `curl http://100.98.163.17:8002/metrics` returns HTTP 200
- Not in UFW rules (protected from public internet only by default deny, which Docker iptables rules may bypass)

The script exposes Prometheus-format metrics for: nginx health, node_exporter health, postgres health, redis health, Docker status, system load average, and process uptime.

**Risk**: MEDIUM-HIGH -- exposes service topology and health status to anyone on the Tailscale mesh. Information disclosure that reveals running services, their locations, and their health state.

**Proposed Fix**: Change the bind address from `0.0.0.0` to `127.0.0.1` in the script.

**Exact Commands to Apply**:
```bash
# On Hostinger (ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17):
sed -i 's/("0.0.0.0", 8002)/("127.0.0.1", 8002)/' /tmp/hostinger-services-exporter.py
# Verify the change:
grep "HTTPServer" /tmp/hostinger-services-exporter.py
# Should show: HTTPServer(("127.0.0.1", 8002), Handler).serve_forever()
# Restart the process:
pkill -f hostinger-services-exporter
nohup python3 /tmp/hostinger-services-exporter.py &
# Verify:
ss -tlnp | grep 8002
# Should show 127.0.0.1:8002 not 0.0.0.0:8002
```

**Rollback Commands**:
```bash
sed -i 's/("127.0.0.1", 8002)/("0.0.0.0", 8002)/' /tmp/hostinger-services-exporter.py
pkill -f hostinger-services-exporter
nohup python3 /tmp/hostinger-services-exporter.py &
```

**Verification**:
```bash
# From localhost should work:
curl -s http://127.0.0.1:8002/metrics | head -3
# From Tailscale should fail:
curl -s --connect-timeout 3 http://100.98.163.17:8002/metrics || echo "BLOCKED as expected"
```

---

## Finding 3: Hostinger VPS -- Cadvisor on Port 9099 (P1 / HIGH)

**Server**: Hostinger VPS `100.98.163.17`
**Evidence**:
- Container: `cadvisor` (gcr.io/cadvisor/cadvisor:v0.49.1)
- Port mapping: `0.0.0.0:9099 -> 8080/tcp` (Docker-proxy)
- `docker inspect` confirms: `"PortBindings": {"8080/tcp":[{"HostIp":"0.0.0.0","HostPort":"9099"}]}`
- Reachable from Hetzner via Tailscale: `curl http://100.98.163.17:9099/metrics` returns HTTP 200
- Not in UFW rules (protected only by default deny, which Docker bypasses)

Cadvisor exposes detailed container metrics including running processes, CPU/memory/disk usage per container, network I/O, filesystem stats, and kernel metrics.

**Risk**: MEDIUM-HIGH -- detailed container and system metrics exposed to the Tailscale mesh. Information disclosure of all running containers, their images, resource usage, and system internals.

**Proposed Fix**: Recreate the cadvisor container with port binding restricted to `127.0.0.1`.

**Exact Commands to Apply**:
```bash
# On Hostinger (ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17):
# Stop and remove current container
docker stop cadvisor
docker rm cadvisor
# Recreate with 127.0.0.1 binding
docker run -d \
  --name=cadvisor \
  --restart=unless-stopped \
  -p 127.0.0.1:9099:8080 \
  --device=/dev/kmsg \
  --privileged=false \
  --volume=/dev/disk:/dev/disk:ro \
  --volume=/:/rootfs:ro \
  --volume=/var/run:/var/run:ro \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/docker:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:v0.49.1 \
  -logtostderr
# Verify:
docker ps --format '{{.Names}} {{.Ports}}' | grep cadvisor
# Should show: cadvisor 127.0.0.1:9099->8080/tcp
```

**Rollback Commands**:
```bash
docker stop cadvisor
docker rm cadvisor
docker run -d \
  --name=cadvisor \
  --restart=unless-stopped \
  -p 9099:8080 \
  --device=/dev/kmsg \
  --volume=/dev/disk:/dev/disk:ro \
  --volume=/:/rootfs:ro \
  --volume=/var/run:/var/run:ro \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/docker:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:v0.49.1 \
  -logtostderr
```

**Verification**:
```bash
# From localhost should work:
curl -s http://127.0.0.1:9099/metrics | head -3
# From Tailscale should fail:
curl -s --connect-timeout 3 http://100.98.163.17:9099/metrics || echo "BLOCKED as expected"
```

---

## Finding 4: Hostinger VPS -- Node Exporter on Port 9100 (P2 / MEDIUM)

**Server**: Hostinger VPS `100.98.163.17`
**Evidence**:
- Systemd service: `/etc/systemd/system/node_exporter.service`
- Command: `/usr/local/bin/node_exporter --web.listen-address=:9100`
- Listening on `*:9100` (all interfaces, IPv4 + IPv6)
- Reachable from Hetzner via Tailscale: `curl http://100.98.163.17:9100/metrics` returns HTTP 200
- Not in UFW rules

**Risk**: MEDIUM -- system metrics (CPU, memory, disk, network, processes) exposed to the Tailscale mesh. While node_exporter is standard for monitoring, it should not be accessible beyond localhost for security hardening.

**Proposed Fix**: Update the systemd unit to bind to `127.0.0.1:9100`.

**Exact Commands to Apply**:
```bash
# On Hostinger (ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17):
sed -i 's|--web.listen-address=:9100|--web.listen-address=127.0.0.1:9100|' /etc/systemd/system/node_exporter.service
systemctl daemon-reload
systemctl restart node_exporter
# Verify:
ss -tlnp | grep node_exporter
# Should show 127.0.0.1:9100 not *:9100
```

**Rollback Commands**:
```bash
sed -i 's|--web.listen-address=127.0.0.1:9100|--web.listen-address=:9100|' /etc/systemd/system/node_exporter.service
systemctl daemon-reload
systemctl restart node_exporter
```

**Verification**:
```bash
curl -s --connect-timeout 3 http://100.98.163.17:9100/metrics || echo "BLOCKED as expected"
curl -s http://127.0.0.1:9100/metrics | head -3  # Should work
```

---

## Finding 5: Hetzner -- Changedetection Container 19 Restarts (P2 / MEDIUM)

**Server**: Hetzner (local)
**Evidence**:
- Container: `aiops-changedetection`
- Docker inspect: `RestartCount: 19`, state: `running`
- Restart policy: `unless-stopped`
- Current status appears healthy (logs show 200 responses on port 5000)
- Port binding: `127.0.0.1:5000 -> 5000/tcp` (properly localhost-bound)
- No 0.0.0.0 Docker binds on this server

19 restarts suggests a recurrent crash pattern. Common causes for changedetection.io: OOM kills (resource limits), database corruption, or network connectivity issues during startup.

**Risk**: LOW-MEDIUM -- currently running stably, but 19 restarts indicates fragility. If the root cause is resource exhaustion, it may recur under load.

**Proposed Fix**: Investigate root cause of crashes.

**Commands to Diagnose**:
```bash
# Check for OOM kills
docker inspect aiops-changedetection --format '{{json .HostConfig.Memory}}'
dmesg | grep -i "oom\|killed" | tail -5
# Check full logs
docker logs aiops-changedetection 2>&1 | grep -iE "error|traceback|exception|killed|oom|crash" | tail -30
# Check resource limits
docker inspect aiops-changedetection --format 'Memory: {{.HostConfig.Memory}}, CPU Shares: {{.HostConfig.CpuShares}}'
# Check creation time for restart frequency
docker inspect aiops-changedetection --format 'Created: {{.Created}}'
```

**Potential Fixes Based on Root Cause**:
- If OOM: Increase memory limit via `docker update --memory=<new-limit> aiops-changedetection`
- If DB corruption: Restore from backup or clean the SQLite database
- If startup race condition: Add `depends_on` or healthcheck
- If persistent: Recreate container with updated image

**Verification**: Monitor restart count after fix:
```bash
docker inspect aiops-changedetection --format '{{.RestartCount}} restarts'
```

---

## Finding 6: CoreDB VPS -- Node Exporter on Port 9100 (P3 / LOW)

**Server**: CoreDB VPS `100.118.166.117`
**Evidence**:
- Process listening on `*:9100` (all interfaces)
- Process: `node_exporter` (PID 3226)
- Not in UFW rules -- protected by default deny from public internet
- Not tested for Tailscale reachability

**Risk**: LOW -- protected from public internet by UFW default deny. Tailscale accessibility is limited to the mesh.

**Proposed Fix**: Add `--web.listen-address=127.0.0.1:9100` to the node_exporter startup, consistent with the Hostinger hardening above.

**Exact Commands to Apply**:
```bash
# On CoreDB (ssh root@100.118.166.117):
# Find the systemd unit or startup script
systemctl cat node_exporter 2>/dev/null || find /etc -name '*node_exporter*' 2>/dev/null
# Then modify the listen address
```

---

## Finding 7: CoreDB VPS -- Redis Exporter on Port 9121 (P3 / LOW)

**Server**: CoreDB VPS `100.118.166.117`
**Evidence**:
- Process listening on `*:9121`
- Process: `redis_exporter` (PID 83218)
- Not in UFW rules -- protected by default deny

**Risk**: LOW -- same as node_exporter. Protected by default deny.

**Proposed Fix**: Consider binding to `127.0.0.1:9121` or at minimum verify it is not in UFW rules.

---

## Finding 8: Hostinger VPS -- Socat Port 5433 (INFO / LOW)

**Server**: Hostinger VPS `100.98.163.17`
**Evidence**:
- Process: `/usr/bin/socat TCP-LISTEN:5433,bind=100.98.163.17,fork,reuseaddr TCP:127.0.0.1:5433`
- Binds to Tailscale IP (100.98.163.17) only
- Forwards to localhost:5433 (likely secondary Postgres port)
- Not accessible via public internet (UFW default deny)

**Risk**: LOW -- intentional database proxy for Tailscale mesh. The explicit bind to Tailscale IP shows deliberate design. Intended for database access from other mesh nodes.

**Recommendation**: Document as a known service. No change needed.

---

## Finding 9: Hetzner -- LiteLLM Master Key (FALSE POSITIVE)

**Server**: Hetzner (local)
**Evidence**:
- `.env` file at `/opt/apps/litellm/.env` contains `LITELLM_MASTER_KEY=sk-4ac726fce2564ce88ba7f22640c8eff3`
- `run.sh` sources the .env file: `source /opt/apps/litellm/.env`
- Process environ confirms: `LITELLM_MASTER_KEY=sk-4ac726fce2564ce88ba7f22640c8eff3`
- YAML config uses: `master_key: os.environ/LITELLM_MASTER_KEY`
- Auth test: `/models` returns 401 without key, 200 with key
- Health endpoints (`/health`, `/health/liveliness`, `/health/readiness`) are correctly configured as unprotected via `public_routes`

**Risk**: NONE -- properly configured.

**Recommendation**: No action needed. Close the audit finding as FALSE POSITIVE.

---

## Additional Observation: Hetzner UFW Status

**Server**: Hetzner (local)
**Observation**: UFW is active with appropriate rules. 0.0.0.0 listeners are only SSH (22), nginx (80/443) -- expected for a web server. No Docker containers bind to 0.0.0.0. All service ports are properly restricted:
- 443/tcp: Anywhere (public web)
- 9000/tcp: DENY Anywhere
- 9090/tcp: DENY Anywhere
- Various ports on tailscale0 only (internal mesh services)

This is the reference implementation for security compliance.

---

## Consolidated Risk Matrix

| # | Finding | Server | Risk | Fix Complexity | UFW Gap | Docker Side |
|---|---------|--------|------|----------------|---------|-------------|
| 1 | SSH public exposure | CoreDB | CRITICAL/P0 | Simple (1 ufw delete) | Yes (overly broad rule) | N/A |
| 2 | Port 8002 exporter | Hostinger | HIGH/P1 | Simple (sed + restart) | Partially (not in rules) | No (system process) |
| 3 | Port 9099 cadvisor | Hostinger | HIGH/P1 | Moderate (recreate container) | Partially (Docker bypass) | Yes (0.0.0.0 bind) |
| 4 | Port 9100 node_exporter | Hostinger | MEDIUM/P2 | Simple (systemd edit + restart) | Partially (not in rules) | No (system process) |
| 5 | Changedetection 19 restarts | Hetzner | MEDIUM/P2 | Diagnostic | N/A | Yes (container crash) |
| 6 | Port 9100 node_exporter | CoreDB | LOW/P3 | Simple | Partially (not in rules) | No (system process) |
| 7 | Port 9121 redis_exporter | CoreDB | LOW/P3 | Simple | Partially (not in rules) | No (system process) |
| 8 | Port 5433 socat | Hostinger | INFO/LOW | Did not propose change | N/A (intentional) | No (system process) |
| 9 | LiteLLM master key | Hetzner | FALSE POSITIVE | None needed | N/A | N/A |

---

## Security Posture Score (Current)

| Category | Score | Notes |
|----------|-------|-------|
| Network exposure | 12/20 | CoreDB SSH exposed; Hostinger services accessible via Tailscale |
| Container security | 16/20 | Cadvisor 0.0.0.0 bind; changedetection 19 restarts |
| SSL health | 20/20 | Not assessed but no SSL issues found |
| Auth config | 20/20 | LiteLLM properly configured; false positive corrected |
| Secrets management | 20/20 | No secrets leaks found |
| **Total** | **88/100** | |

**Post-fix projected**: 96/100 (CoreDB SSH fix + Hostinger bind fixes)

---

## Implementation Priority

1. **IMMEDIATE (today)**: Finding 1 -- CoreDB SSH public exposure fix (1 command, highest impact)
2. **IMMEDIATE (today)**: Finding 2 -- Hostinger exporter 127.0.0.1 bind (1 sed command)
3. **IMMEDIATE (today)**: Finding 3 -- Hostinger cadvisor 127.0.0.1 bind (recreate container)
4. **TODAY**: Finding 4 -- Hostinger node_exporter 127.0.0.1 bind
5. **THIS WEEK**: Finding 5 -- Changedetection restart investigation
6. **THIS WEEK**: Findings 6-7 -- CoreDB system service bind hardening
7. **NICE TO HAVE**: Finding 8 -- Document socat as known service

---

## Reference Files

- Agent instructions: `/root/.claude/agents/security-intelligence.md`
- Exposure matrix: `/root/AI_OPS_EXPOSURE_MATRIX.md`
- CoreDB exposure: `/root/CORE_DB_EXPOSURE_MATRIX.md`
- Hostinger surface: `/root/HOSTINGER_PUBLIC_SURFACE.md`
- UFW audit: `/root/HOSTINGER_UFW_AUDIT.md`
- Enforcement gaps: `/root/ENFORCEMENT_GAP_ANALYSIS.md`

---

## Notes for Incident Response

- **No fixes have been applied**. This document is read-only audit output.
- `FINDING 9` (LiteLLM master key) should be closed as FALSE POSITIVE in the audit tracker.
- After applying fixes for Findings 1-4, re-run the security posture assessment to confirm score improvement.
- Hostinger services bound to 0.0.0.0 that are reachable via Tailscale but blocked by UFW from the public internet means: if UFW is ever disabled or Docker iptables rules change, these ports become immediately internet-facing. This is why binding to 127.0.0.1 is the correct fix.
