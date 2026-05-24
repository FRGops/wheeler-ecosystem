# Hostinger Stage 2 Cleanup Plan
**Server:** wheeler-aiops-01 | **Date:** 2026-05-24 | **STATUS: PLAN ONLY — DO NOT EXECUTE**

---

## Executive Summary

The server has **95 UFW rules** with ~20 duplicates and 7 stale entries. **8 admin dashboards** are exposed to the public internet due to a UFW rule-ordering contradiction. **14 Docker containers** bind to `0.0.0.0`, creating a parallel access path that bypasses the correctly-configured nginx Tailscale-only gateway. The firewall intent is sound (admin on tailscale0, public only 22/80) but the implementation is undermined by later Anywhere ALLOW rules and broad 0.0.0.0 Docker bindings.

**This plan is organized by risk — each phase is self-contained and can be rolled back independently.**

---

## Phase 0: Preparation (Before Any Changes)

### 0.1 — Snapshot Current State
```bash
ufw status numbered > /root/cleanup/ufw-backup-$(date +%Y%m%d).txt
docker ps --format "table {{.Names}}\t{{.Ports}}" > /root/cleanup/docker-ports-backup-$(date +%Y%m%d).txt
ss -tulpn > /root/cleanup/ports-backup-$(date +%Y%m%d).txt
pm2 save  # snapshot current PM2 state
```

### 0.2 — Verify Tailscale Connectivity
```bash
tailscale status  # confirm all 4 nodes reachable
ping -c 3 100.121.230.28  # self
```

---

## Phase 1: UFW — Close Admin Panels to Internet (CRITICAL, Low Risk)

**Risk:** None. All admin panels are also accessible via Tailscale → nginx.

### Actions:
1. Delete the Anywhere ALLOW rules that expose admin panels (rules 30-35, 37-39, 41):
   ```bash
   # Delete in REVERSE order (highest number first) to preserve numbering
   ufw delete 41   # 8090 - 1panel (CRITICAL)
   ufw delete 39   # 19999 - netdata
   ufw delete 38   # 3001 - uptime-kuma
   ufw delete 37   # 5001 - stale (nothing listening)
   ufw delete 35   # 3130 - healthchecks
   ufw delete 34   # 5000 - changedetection
   ufw delete 33   # 3002 - grafana
   ufw delete 32   # 8088 - superset
   ufw delete 31   # 8007 - surplusai-scraper-agent
   ufw delete 30   # 8098 - prediction-radar
   ```

2. **Verify:** `curl -m 3 http://5.78.140.118:3002` should now fail (Grafana no longer reachable from internet)

3. **Verify Tailscale path still works:** `curl -k https://grafana.aiops` from a Tailscale-connected machine

### After Phase 1:
- 8 admin panels dark from internet instantly
- All still accessible via Tailscale → nginx
- UFW reduced by 10 rules

---

## Phase 2: UFW — Remove Duplicate Rule Blocks (MEDIUM, Low Risk)

**Risk:** None. These rules are fully redundant — removing them changes zero access patterns.

### Actions:
1. Delete entire Group B (rules 18-29) — all 100.64.0.0/10 duplicates:
   ```bash
   ufw delete 29   # 8123
   ufw delete 28   # 9090
   ufw delete 27   # 19999
   ufw delete 26   # 3001
   ufw delete 25   # 5001
   ufw delete 24   # 9000
   ufw delete 23   # 3130
   ufw delete 22   # 5000
   ufw delete 21   # 3002
   ufw delete 20   # 8088
   ufw delete 19   # 8007
   ufw delete 18   # 8098
   ```

2. Delete stale rules:
   ```bash
   ufw delete 13   # 5001 stale (after renumbering)
   ufw delete 51   # 4000 stale
   ufw delete 50   # 3000 misconfigured
   ```

3. Delete duplicate rules:
   ```bash
   ufw delete 49   # 22 duplicate of #48
   ufw delete 46   # 5434 duplicate of #17
   ufw delete 59   # 5433 duplicate of #55
   ```

### After Phase 2:
- UFW reduced by ~18 more rules
- Rule list becomes readable and auditable
- No access changed — all deletions are pure redundancy

---

## Phase 3: Docker — Re-bind to 127.0.0.1 (HIGH, Medium Risk)

**Risk:** If a service has a legitimate non-nginx consumer that connects via the public IP, it will break. Test each service after re-binding.

### 3.1 — Services to Re-bind (ordered by risk)

Each container needs its port mapping changed from `0.0.0.0:PORT:INTERNAL` to `127.0.0.1:PORT:INTERNAL`:

| Container | Current | Target | Command Pattern |
|-----------|---------|--------|-----------------|
| aiops-grafana | 0.0.0.0:3002 | 127.0.0.1:3002 | docker stop → docker rm → docker run with 127.0.0.1 binding |
| aiops-superset | 0.0.0.0:8088 | 127.0.0.1:8088 | same pattern |
| aiops-clickhouse | 0.0.0.0:8123 | 127.0.0.1:8123 | **CRITICAL — database** |
| uptime-kuma | 0.0.0.0:3001 | 127.0.0.1:3001 | |
| netdata | 0.0.0.0:19999 | 127.0.0.1:19999 | |
| langflow | 0.0.0.0:7860 | 127.0.0.1:7860 | |
| docuseal | 0.0.0.0:3010 | 127.0.0.1:3010 | |
| aiops-changedetection | 0.0.0.0:5000 | 127.0.0.1:5000 | |
| aiops-healthchecks | 0.0.0.0:3130 | 127.0.0.1:3130 | |
| aiops-prometheus | 0.0.0.0:9090 | 127.0.0.1:9090 | |
| loki | 0.0.0.0:3100 | 127.0.0.1:3100 | |
| promtail | 0.0.0.0:9080 | 127.0.0.1:9080 | |
| hostinger-health-exporter | 0.0.0.0:9091 | 127.0.0.1:9091 | |
| prediction-radar-app-web | 0.0.0.0:8098 | 127.0.0.1:8098 | |

### 3.2 — Verify Each Service After Re-binding

```bash
# Container should still be reachable via nginx (Tailscale path)
curl -k -H "Host: grafana.aiops" https://100.121.230.28/
# Container should NOT be reachable directly
curl -m 3 http://5.78.140.118:3002  # should fail
```

### After Phase 3:
- 14 containers no longer directly reachable from internet
- nginx → 127.0.0.1 path continues to work
- Defense in depth: even if UFW fails, Docker bindings prevent exposure

---

## Phase 4: Host-Network Containers (MEDIUM, High Effort)

**Risk:** Requires Docker Compose file modifications. May need Temporal reconfiguration.

### 4.1 — Assess Dependencies
- `temporal-temporal-ui-1` (port 8089 on all interfaces): Admin UI. Likely only needed via Tailscale.
- `temporal-temporal-1` (ports on 127.0.1.1): Already safe — loopback-bound.
- `usesend` (port 8005 on all interfaces): Needs investigation — what consumes this?

### 4.2 — Migration Options
**Option A (Quick):** Add UFW rules to block these ports from non-Tailscale traffic, then re-bind the process to 127.0.0.1 if possible.
**Option B (Proper):** Move containers to bridge networking with explicit port mappings to 127.0.0.1.

### Recommended: Option A for temporal-ui, Option B for usesend

```bash
# Quick fix for temporal-ui
ufw insert 1 deny from any to any port 8089
ufw insert 2 allow from 100.64.0.0/10 to any port 8089
```

---

## Phase 5: SSH Hardening (MEDIUM, Medium Risk)

**Risk:** If Tailscale is down, lose SSH access. Keep a fallback or test carefully.

### Option A: Tailscale-Only SSH
```bash
# In /etc/ssh/sshd_config:
ListenAddress 100.121.230.28:22  # Tailscale IP only
# Remove ListenAddress 0.0.0.0:22
```

### Option B: Keep Public SSH, Add Restrictions
```bash
# Already have LIMIT on port 22 — sufficient for now
# Consider: disable password auth, enforce key-only
```

**Recommendation:** Option B for now (keep emergency access). Revisit after Tailscale stability is proven over 30 days.

---

## Phase 6: IPv6 Rules (LOW, Low Risk)

If IPv6 is not actively used on the public interface:
```bash
# Delete rules 60-95 (all IPv6 mirrors)
# Verify with: ip -6 addr show eth0  # check if IPv6 is configured
```

---

## Phase 7: Remaining Items

### 7.1 — UFW Broad Subnet Rules
Rules 52 (172.16.0.0/12) and 53 (10.0.0.0/8) allow all protocols from entire private ranges. If these are only needed for specific services, narrow them:
```bash
# Replace broad allows with specific port rules
ufw delete 52
ufw delete 53
ufw allow from 10.0.0.0/16 to any port 5433 proto tcp  # example
```

### 7.2 — Port 80 Dead Listener
The system nginx opens 0.0.0.0:80 via a systemd socket but has no server block configured. Either:
- Add a redirect to close the port: `return 301 https://...`
- Remove the systemd socket activation

### 7.3 — Environment Variable Hygiene
- Migrate `DEEPSEEK_API_KEY`, `OPENAI_API_KEY`, DB passwords from hardcoded `ecosystem.config.js` to `.env` files
- Clean `openclaw-dashboard` PM2 environment (remove Claude Code session tokens)
- Standardize the `surplusai-scraper-agent-svc` API key (currently different from all other agents)

### 7.4 — Config Cleanup
- Archive `/opt/wheeler/ecosystem.config.js` (stale config tree with conflicting port assignments)
- Remove `surplusai-portal-frontend` (port 3003) tailscale0 UFW rule if the service has been migrated to EDGE

### 7.5 — Verify No Redis/DB Exposures
Both Postgres instances and all Redis instances are correctly bound to 127.0.0.1 or Docker-internal. No action needed — this is well-configured.

---

## Rollback Plan

Every phase is independently reversible:

| Phase | Rollback |
|-------|----------|
| 1 | Re-add deleted UFW rules from backup |
| 2 | Re-add deleted UFW rules from backup |
| 3 | Re-create containers with original `0.0.0.0` port bindings |
| 4 | Remove UFW deny rules for temporal-ui |
| 5 | Revert sshd_config to `ListenAddress 0.0.0.0` |
| 6 | N/A (if IPv6 wasn't used, no impact) |
| 7 | Re-add broad subnet rules if needed |

---

## Risk Matrix

| Phase | Risk Level | Impact if Wrong | Recovery Time |
|-------|-----------|-----------------|---------------|
| 1 | Low | None (Tailscale path still works) | < 1 minute |
| 2 | Low | None (pure duplicates) | < 1 minute |
| 3 | Medium | Service unreachable if non-nginx consumer exists | < 5 minutes per container |
| 4 | Medium | Temporal UI unreachable | < 2 minutes |
| 5 | Medium | Locked out of SSH if Tailscale down | May need console access |
| 6 | Low | None (if IPv6 unused) | < 1 minute |
| 7 | Varies | Depends on specific change | Varies |

---

## Recommended Execution Order

1. **Phase 1** (immediate) — Close admin panels to internet. Highest impact, lowest risk. ~15 minutes.
2. **Phase 2** (same session) — Remove duplicates. Cleanup while in the firewall. ~10 minutes.
3. **Phase 3** (scheduled maintenance window) — Docker re-binding. Test each service. ~1-2 hours.
4. **Phase 7.3** (separate PR) — Env var hygiene. Code change, not infra. No downtime.
5. **Phases 4-5** (planning required) — Host-network and SSH. Need more context.
6. **Phase 6** (whenever) — IPv6 cleanup. Low priority.

**Total Phase 1+2 time: ~25 minutes. Impact: 8 critical/high exposures eliminated.**
