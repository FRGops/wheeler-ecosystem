# Security Configuration Fixes

**Date:** 2026-05-27
**Audit:** Wheeler Ecosystem 87/100 -> 95+/100 Gap Analysis
**Type:** Targeted security and configuration remediation (non-destructive)

---

## Fix 1: LITELLM_MASTER_KEY Validation

### Issue
Config at `/root/.claude/litellm-deepseek.yaml` references `master_key: os.environ/LITELLM_MASTER_KEY`. The active LiteLLM PM2 process (script: `/opt/apps/litellm/run.sh`) sources `/opt/apps/litellm/.env`, and that file **already contains** the key:
```
LITELLM_MASTER_KEY=sk-4ac726fce2564ce88ba7f22640c8eff3
```
Initial check showed the env var as "set but empty" in the current shell -- this was a false alarm. The var is properly set in the `.env` file sourced at process start.

### Evidence
- Config: `/root/.claude/litellm-deepseek.yaml` line 44 has `master_key: os.environ/LITELLM_MASTER_KEY`
- .env file: `/opt/apps/litellm/.env` contains `LITELLM_MASTER_KEY=sk-4ac726fce2564ce88ba7f22640c8eff3`
- Run script: `/opt/apps/litellm/run.sh` sources the .env with `set -a` (export mode) before launching LiteLLM

### Generated Fallback Key (for rotation)
```
a94a67718b46b467e4025fb636c3b2a810fd4d5d999bdc691889da50e745a36d
```

### Verification Command
```bash
# Check the .env file has the key
grep LITELLM_MASTER_KEY /opt/apps/litellm/.env

# Verify LiteLLM is running and responding
curl -s http://127.0.0.1:4049/health | head -5

# Check PM2 process env (should NOT show the key thanks to PM2 daemon cleanup)
pm2 show litellm | grep -i master
```

### Risk Assessment
- **None.** The key is already configured. The generated key above provides a rotation option.
- The existing key `sk-4ac726fce2564ce88ba7f22640c8eff3` appears to be a short (32 hex chars = 128 bits without the `sk-` prefix). Recommend rotating to the generated 256-bit key during next maintenance window.

### Rollback
Revert to previous key in `/opt/apps/litellm/.env` and restart LiteLLM:
```bash
pm2 delete litellm && pm2 start /opt/apps/litellm/run.sh --name litellm
```

---

## Fix 2: Hostinger Port 8002 Exposure

### Issue
A Python3 Prometheus exporter (`hostinger-services-exporter.py`) is running on **0.0.0.0:8002** (PID 3298522). This exporter exposes system health metrics publicly. The `ss -tlnp` confirms:
```
LISTEN 0 5 0.0.0.0:8002 0.0.0.0:* users:(("python3",pid=3298522,fd=3))
```

### Evidence
- Process: `python3 /tmp/hostinger-services-exporter.py`
- Metrics exposed: nginx, node_exporter, postgres, redis, docker health checks, system load
- **Current script file ALREADY fixed:** The script at `/tmp/hostinger-services-exporter.py` now contains `HTTPServer(("127.0.0.1", 8002), Handler).serve_forever()` -- binds to 127.0.0.1
- The running process is a stale instance from before the script was corrected

### Exact Fix Commands (Hostinger via SSH)
```bash
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17

# Verify script already has 127.0.0.1
grep 'HTTPServer' /tmp/hostinger-services-exporter.py
# Expected: HTTPServer(("127.0.0.1", 8002), Handler).serve_forever()

# Kill and restart with fixed script
kill 3298522
cd /tmp && nohup python3 hostinger-services-exporter.py &

# Verify new process binds to 127.0.0.1
ss -tlnp | grep 8002
# Expected: LISTEN 0 5 127.0.0.1:8002 ...
```

### Risk Assessment
- **Low.** The script already has the fix. Only the running process is stale.
- Metrics exporter is low-risk, internal-only tool. Killing and restarting causes < 1s gap in metrics collection.
- No dependencies depend on port 8002 being accessible externally (exporter is standalone).

### Rollback
```bash
# Restart with 0.0.0.0 binding (old behavior)
kill <NEW_PID>
nohup python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess, time, socket
# ... (original code with 127.0.0.1 changed back to 0.0.0.0)
" &
```

---

## Fix 3: Hostinger Cadvisor 0.0.0.0:9099

### Issue
Cadvisor container (`gcr.io/cadvisor/cadvisor:v0.49.1`) exposes its web UI and metrics on **0.0.0.0:9099**. The container was started with default Docker bridge networking and port `0.0.0.0:9099->8080/tcp`.

### Evidence
- Container: `cadvisor` (created 2026-05-24, restart: unless-stopped)
- Port mapping confirms: `"HostIp": "0.0.0.0", "HostPort": "9099"`
- Prometheus scrapes cadvisor via `172.22.0.1:9099` (Docker bridge gateway = host IP)
- No docker-compose file associatd (container has no compose labels) -- started via `docker run`

### Challenge with 127.0.0.1 Change
Changing cadvisor to `127.0.0.1:9099` would **break Prometheus scraping**. The monitoring Prometheus container scrapes cadvisor via the Docker bridge gateway IP `172.22.0.1:9099`, which would become unreachable if cadvisor binds only to localhost.

### Proposed Fix (UFW-based -- safer than binding change)
Since cadvisor must remain reachable from Docker containers (Prometheus), the correct approach is UFW-level restriction:

```bash
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17

# Allow cadvisor port only from internal networks
ufw allow in on tailscale0 proto tcp to any port 9099 comment 'cadvisor - tailscale'
ufw allow in on docker0 proto tcp to any port 9099 comment 'cadvisor - docker containers'
ufw deny in on eth0 proto tcp to any port 9099 comment 'cadvisor - block external'

# Alternative: If Tailscale is the only access needed
ufw delete deny in on eth0 proto tcp to any port 9099
ufw deny 9099 comment 'cadvisor - blocked from external'
```

### Alternative: Recreate container with 127.0.0.1 + Docker network
If Prometheus is on the same Docker network as cadvisor (or can be connected), remove the port bind entirely and connect via internal Docker networking:
```bash
docker stop cadvisor && docker rm cadvisor
docker run -d --name=cadvisor --restart=unless-stopped \
  --net=host \
  --pid=host \
  --privileged \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:ro \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  -v /dev/disk/:/dev/disk:ro \
  gcr.io/cadvisor/cadvisor:v0.49.1 \
  -logtostderr
# With --net=host, cadvisor is at host IP on its default 8080
# Update prometheus.yml target from "172.22.0.1:9099" to "host.docker.internal:8080"
```
--but this requires privileged mode and a container replacement. Documented for next maintenance window.

### Risk Assessment
- **Low (for UFW approach).** UFW rules block external access while preserving internal Prometheus scraping.
- **Medium (for --net=host approach).** Requires container replacement and prometheus config change.

### Rollback
```bash
ufw delete deny 9099
# OR
ufw delete allow in on docker0 proto tcp to any port 9099
```

---

## Fix 4: CoreDB SSH Restrict to Tailscale Only

### Issue
CoreDB UFW has rule 3: `22/tcp ALLOW IN Anywhere` -- SSH is open to the entire internet. While fail2ban is active and working (478 total failed, 3 currently banned from China/Russia IPs), this is defense-in-depth failure. The firewall should drop external SSH before fail2ban even sees it.

### Current UFW Rules (relevant)
```
[ 1] 22 on tailscale0           ALLOW IN    Anywhere          # tailscale-only SSH (GOOD)
[ 2] 22                         ALLOW IN    10.0.0.0/16        # Docker internal network
[ 3] 22/tcp                     ALLOW IN    Anywhere          # WIDE OPEN (BAD)
```

### fail2ban Status
- Jail `sshd`: Active, filter = `_SYSTEMD_UNIT=ssh.service + _COMM=sshd`
- Currently banned: 220.119.37.141, 45.148.10.141, 45.148.10.152
- fail2ban uses journald for detection, not ufw -- removing the ufw rule will NOT break fail2ban
- In fact, once ufw blocks at the firewall level, fail2ban won't see SSH attempts at all (they won't reach sshd), making fail2ban unnecessary for external SSH protection

### Exact Fix Commands
```bash
ssh root@100.118.166.117

# REMOVE rule 3 (22/tcp ANYWHERE) -- must use correct rule number
ufw delete 3

# Verify only tailscale + Docker internal remain
ufw status numbered | grep '22\|SSH'
# Expected:
# [ 1] 22 on tailscale0           ALLOW IN    Anywhere
# [ 2] 22                         ALLOW IN    10.0.0.0/16
```
Note: Rule numbers shift after deletion. If rule 3 is now gone, remaining rules renumber. Verify after deletion.

### Risk Assessment
- **Low.** SSH via Tailscale (rule 1) and Docker internal (rule 2, 10.0.0.0/16) remain permitted.
- Removing the wide-open rule means SSH from the public internet is blocked entirely -- this is the **desired state**.
- fail2ban will stop seeing external SSH attempts (they won't reach sshd), which is fine -- firewall blocking is superior to rate-limiting.
- If you need to SSH from outside Tailscale (e.g., from a Tailscale-incompatible device), consider a VPN or SSH tunnel instead of reopening the firewall.
- **NOT APPLIED** -- requires explicit confirmation per audit policy.

### Rollback
```bash
ufw allow 22/tcp
# This adds a new rule; verify ordering with 'ufw status numbered'
```

---

## Fix 5: Grafana Dashboards Provisioning

### Issue
The `aiops-grafana` monitoring stack (port 3002) has no provisioning setup. It uses only a volume mount: `monitoring_grafana-data:/var/lib/grafana`. The `prediction-radar-grafana` already has proper provisioning with bind mounts.

### Provisioning Files Created

**Datasource:** `/opt/apps/monitoring/grafana/provisioning/datasources/prometheus.yml`
```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
```

**Dashboard provider:** `/opt/apps/monitoring/grafana/provisioning/dashboards/default.yml`
```yaml
apiVersion: 1
providers:
  - name: 'Wheeler AIOps'
    orgId: 1
    folder: 'Wheeler AIOps'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
```

**Docker compose updated:** Added bind mounts to `/opt/apps/monitoring/docker-compose.yml`:
```yaml
volumes:
  - grafana-data:/var/lib/grafana
  - ./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro    # NEW
  - ./grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro      # NEW
```

### Activate (Requires Restart)
```bash
cd /opt/apps/monitoring
docker compose up -d grafana
# This restarts only the grafana container, not prometheus/alertmanager
```

### Adding Dashboards Programmatically
Once provisioning is active, dashboards can be added three ways:

1. **JSON file placement:** Export a dashboard as JSON and place it in:
   ```bash
   # Dashboard JSON files in this directory are auto-loaded
   /opt/apps/monitoring/grafana/dashboards/
   # (directory exists but may need creation)
   mkdir -p /opt/apps/monitoring/grafana/dashboards
   ```

2. **Grafana API** (no restart needed):
   ```bash
   # Get grafana API key first (default admin:admin on port 3002)
   curl -s -X POST -H "Content-Type: application/json" \
     -d '{"name":"apikey","role":"Admin"}' \
     http://admin:admin@127.0.0.1:3002/api/auth/keys
   
   # Import dashboard JSON via API
   curl -s -X POST -H "Content-Type: application/json" \
     -d '{"dashboard":{"title":"Wheeler Overview","panels":[]},"overwrite":true}' \
     http://admin:admin@127.0.0.1:3002/api/dashboards/db
   ```

3. **Grafana Admin UI:** Navigate to http://127.0.0.1:3002 -> Connections -> Datasources -> Add Prometheus
   - URL: `http://prometheus:9090` (Docker internal hostname)
   - Access: Server (default)

### Risk Assessment
- **None (files created, docker-compose updated but not restarted).**
- Provisioning files are read-only (`:ro` mount) and cannot corrupt the grafana-data volume.
- Dashboard provider watches for files. If the `dashboards/` directory is empty, no dashboards are loaded.
- Will take effect on next `docker compose up -d grafana`.

### Rollback
```bash
# Revert docker-compose.yml to original grafana volumes section
# Remove the two provisioning bind mount lines
cd /opt/apps/monitoring
git checkout docker-compose.yml  # if tracked, or edit manually
docker compose up -d grafana
```

---

## Summary Score Impact

| Fix | Gap Area | Points Gained* | Status |
|-----|----------|----------------|--------|
| 1 - LITELLM_MASTER_KEY | Already configured | 0 | Verified OK |
| 2 - Port 8002 exposure | Network exposure (+5) | +5 | Fix ready in script, stale process needs kill |
| 3 - Cadvisor 9099 exposure | Network exposure (+3) | +3 | UFW rule proposed (service restart needed) |
| 4 - CoreDB SSH wide open | Network exposure (+5) | +5 | DOCUMENTED - requires human approval |
| 5 - Grafana provisioning | Config mgmt (+2) | +2 | Files created, docker-compose updated |
| **Total** | | **+10 to +15** | |

*Rough estimate; exact score depends on Weighting in security posture model. With fixes 2-5 applied, ecosystem would reach approximately **97-100/100** depending on other factors.

---

## Files Changed

| File | Change |
|------|--------|
| `/opt/apps/monitoring/grafana/provisioning/datasources/prometheus.yml` | Created - Prometheus datasource |
| `/opt/apps/monitoring/grafana/provisioning/dashboards/default.yml` | Created - Dashboard provider |
| `/opt/apps/monitoring/docker-compose.yml` | Updated - added provisioning bind mounts for grafana |

## Files Referenced (read-only, not modified)

| File | Purpose |
|------|---------|
| `/root/.claude/litellm-deepseek.yaml` | LiteLLM active config |
| `/opt/apps/litellm/.env` | LiteLLM environment variables |
| `/opt/apps/litellm/run.sh` | LiteLLM launch script |
| `/tmp/hostinger-services-exporter.py` | Hostinger metrics exporter (already has 127.0.0.1 fix) |
| `/opt/apps/prediction-radar-app/monitoring/prometheus.yml` | Hostinger prometheus config (scrapes cadvisor) |
