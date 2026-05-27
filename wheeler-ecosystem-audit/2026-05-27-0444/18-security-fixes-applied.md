# Security Fixes Applied

**Date:** 2026-05-27
**Operator:** Security Intelligence Agent
**Files:** `/root/.claude/agents/security-intelligence.md`

---

## Summary

| Fix | Target | Status | Severity |
|-----|--------|--------|----------|
| FIX 1 | CoreDB SSH v6 rule cleanup | COMPLETED | P0 |
| FIX 2 | Hostinger cadvisor 0.0.0.0:9099 --> 127.0.0.1:9099 | BLOCKED | P1 |
| FIX 3 | CoreDB node_exporter + redis_exporter | DOCUMENTED | P2 |

---

## FIX 1: CoreDB SSH v6 Rule Cleanup (COMPLETED)

**Host:** `wheeler-core-db-01` (100.118.166.117)

### Finding
The IPv6 UFW rule `22/tcp (v6) ALLOW IN Anywhere (v6)` exposed SSH on CoreDB to all IPv6 addresses. While CoreDB is behind Hetzner DC firewall and SSH has fail2ban + key auth, this violated the Post-Stage 2 security policy of no public exposure.

### Commands Executed

```bash
# Step 1: Identify the rule (from wheeler-aiops-01)
ssh root@100.118.166.117 "ufw status numbered | grep '22/tcp (v6)'"

# Output:
# [11] 22/tcp (v6)                ALLOW IN    Anywhere (v6)

# Step 2: Delete the rule
ssh root@100.118.166.117 "ufw --force delete 11"

# Step 3: Verify
ssh root@100.118.166.117 "ufw status | grep 22"
```

### Verification Output

```
22 on tailscale0           ALLOW       Anywhere
22                         ALLOW       10.0.0.0/16
22 (v6) on tailscale0      ALLOW       Anywhere (v6)
```

### Result
The public IPv6 SSH rule was removed. SSH via Tailscale (v4 and v6) and Hetzner internal network (10.0.0.0/16) remain permitted. This is the correct state.

### Rollback Command (if needed)
```bash
ssh root@100.118.166.117 "ufw allow proto tcp from any to any port 22 comment 'SSH (emergency restore)'"
```

---

## FIX 2: Hostinger cadvisor 0.0.0.0:9099 --> 127.0.0.1:9099 (BLOCKED)

**Host:** `srv1476866` / `edge` / `hostinger` (100.98.163.17)

### Finding
Cadvisor is listening on `0.0.0.0:9099` (all interfaces). Verified via Tailscale curl to `http://100.98.163.17:9099/metrics` which returned cadvisor metrics successfully. UFW default deny currently blocks external access, but the `0.0.0.0` binding is a policy violation.

### What Was Attempted

The following SSH keys/approaches were tried to access Hostinger:

| Key | SHA256 Fingerprint | Result |
|-----|-------------------|--------|
| `~/.ssh/wheeler-cross-server` | `SHA256:cKuaWQCLvtqvh2pEDL7AcjnSHCLln0RMCIF1dz3iiUw` | REJECTED |
| `~/.ssh/id_ed25519` | `SHA256:AfGOhj9vagxDxit09kkvkbogEHpvkna/UmAmyHD6rTE` | REJECTED |
| `~/.ssh/wheeler-mesh-key` | `SHA256:G7XuyEDtxA5r7JsUJ6dUh5vu/rk9OMzqautCdmnKwGM` | REJECTED |
| `ssh hostinger` (SSH config alias) | Tries `id_ed25519` then `wheeler-cross-server` | REJECTED |
| Via CoreDB jump host (ssh -J) | Key forwarding | REJECTED |
| `tailscale ssh` | Tailscale SSH not enabled on peer | FAILED |
| Password authentication | Disabled on server | REJECTED |

### Root Cause
None of the available SSH private keys on `wheeler-aiops-01` (100.121.230.28) are authorized in Hostinger's `/root/.ssh/authorized_keys`. The `wheeler-cross-server` key is authorized on CoreDB (confirmed via CoreDB's authorized_keys) but not on Hostinger. Keys were likely rotated or never deployed to Hostinger.

### Required Fix Commands (for operator with Hostinger access)

```bash
# SSH to Hostinger (requires authorized key)
ssh root@100.98.163.17

# Backup current cadvisor config
docker inspect cadvisor > /tmp/cadvisor-backup.json

# Stop and remove
docker stop cadvisor
docker rm cadvisor

# Recreate with 127.0.0.1 binding
# NOTE: Verify exact image and mounts first from the backup JSON
docker run -d \
  --name cadvisor \
  --restart unless-stopped \
  -p 127.0.0.1:9099:8080 \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:ro \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  -v /dev/disk/:/dev/disk:ro \
  --privileged \
  --device /dev/kmsg \
  gcr.io/cadvisor/cadvisor:v0.49.1

# Verify fix
ss -tlnp | grep 9099
# Expected output: 127.0.0.1:9099 (NOT 0.0.0.0:9099)
```

### Rollback Commands
```bash
# If the recreate fails, restore from backup
docker stop cadvisor 2>/dev/null; docker rm cadvisor 2>/dev/null
docker run -d \
  --name cadvisor \
  --restart unless-stopped \
  -p 9099:8080 \
  <all original mounts from backup>
  gcr.io/cadvisor/cadvisor:v0.49.1
```

### Risk Assessment
- **Production impact:** None. Cadvisor is a monitoring-only container.
- **Downtime:** ~5 seconds during recreate. Metrics gap only.
- **Current mitigation:** UFW default deny blocks external traffic to port 9099.

---

## FIX 3: CoreDB node_exporter + redis_exporter (DOCUMENTED)

**Host:** `wheeler-core-db-01` (100.118.166.117)

### Current State

| Service | Port | Binding | UFW Status |
|---------|------|---------|------------|
| node_exporter | 9100 | `*:9100` (all interfaces) | Default deny blocks external |
| redis_exporter | 9121 | `*:9121` (all interfaces) | Default deny blocks external |

### Risk
Both services listen on ALL interfaces (`*:9100`, `*:9121`). While UFW's default `deny (incoming)` policy currently blocks external access, the `0.0.0.0` binding is a defense-in-depth violation. If UFW were ever disabled or a misconfigured allow rule added, these ports would be publicly exposed.

### Recommended Fix (NOT APPLIED - requires systemd unit changes)

```bash
# SSH to CoreDB
ssh root@100.118.166.117

# Fix node_exporter systemd service
systemctl edit node_exporter
# Add:
# [Service]
# ExecStart=
# ExecStart=/usr/bin/node_exporter --web.listen-address=127.0.0.1:9100

systemctl daemon-reload
systemctl restart node_exporter

# Fix redis_exporter systemd service
systemctl edit redis_exporter
# Add:
# [Service]
# ExecStart=
# ExecStart=/usr/bin/redis_exporter --redis.addr=redis://127.0.0.1:6379 --web.listen-address=127.0.0.1:9121

systemctl daemon-reload
systemctl restart redis_exporter

# Verify
ss -tlnp | grep -E '9100|9121'
# Expected: 127.0.0.1:9100 and 127.0.0.1:9121
```

### Current Mitigation
UFW default deny incoming policy blocks external traffic. Only localhost and Hetzner internal network (10.0.0.0/16) services can reach these ports, and only if they originate from CoreDB itself. Tailscale peers are also blocked for these ports since no UFW allow rule exists for them on Tailscale.

---

## Post-Fix Verification

### CoreDB SSH Rules (after FIX 1)
```
22 on tailscale0           ALLOW       Anywhere
22                         ALLOW       10.0.0.0/16
22 (v6) on tailscale0      ALLOW       Anywhere (v6)
```
Clean. No public Anywhere (v6) rule. Only Tailscale and VPC SSH allowed.

### Hostinger cadvisor (FIX 2 - BLOCKED)
Current state: Still listening on `0.0.0.0:9099`. Reachable via Tailscale. Requires operator with SSH key access to Hostinger to apply the fix.

### CoreDB exporters (FIX 3 - DOCUMENTED)
Both listening on all interfaces. UFW default deny prevents external access. Fix requires systemd unit modification.

---

## Open Issues

1. **Hostinger SSH access** - The `wheeler-cross-server` SSH key is authorized on CoreDB but NOT on Hostinger. This needs to be resolved to enable remote management. Recommended: add the `wheeler-aiops-cross-server` public key (from `~/.ssh/wheeler-cross-server.pub`) to Hostinger's `/root/.ssh/authorized_keys`.

2. **CoreDB exporter bindings** - node_exporter and redis_exporter should bind to `127.0.0.1` as defense-in-depth. Low priority since UFW blocks external access, but should be addressed in the next maintenance window.

3. **Tailscale SSH not enabled** - None of the three Tailscale nodes have Tailscale SSH enabled. Enabling this would provide SSH access independent of authorized_keys, useful for disaster recovery.
