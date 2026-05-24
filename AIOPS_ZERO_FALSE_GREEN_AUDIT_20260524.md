# ZERO FALSE GREEN AUDIT -- Wheeler Ecosystem
**Date:** 2026-05-24 20:54 UTC
**Method:** Direct verification against live system state (no assumption, no inherited claims)

---

## CLAIMS AUDIT

### Claim 1: All 37 Docker containers healthy and bound to 127.0.0.1
**Status: CONTRADICTED**

Evidence:
- Running containers: **42** (not 37). The count in the scorecard is wrong by 5 containers.
- 2 containers lack HEALTHCHECK definitions and therefore are NOT "healthy":
  - `prediction-radar-fincept` -- running, no HEALTHCHECK defined
  - `prediction-radar-crowdsec` -- running, no HEALTHCHECK defined
  - Docker `(healthy)` marker is absent on both; they are "Up" but not "healthy"
- 40/42 containers report `(healthy)`. Both non-healthchecked containers ARE running, just not proven healthy.
- All host-bound container ports are on 127.0.0.1 EXCEPT `usesend` which also binds to `100.121.230.28:3007` (Tailscale IP). The scorecard acknowledges this Tailscale bind.

Gap: Container count off by 5. Two containers without HEALTHCHECK. The scorecard overstates both the count and the health status.

---

### Claim 2: 19/20 PM2 processes online (backup-verification is stopped)
**Status: CONFIRMED**

Evidence:
- 19 of 20 PM2 processes are `online`
- `backup-verification` is `stopped` with pid=0 (intentional)
- `design-agent-svc` has 2 restarts in its history (minor, currently stable)
- Total PM2 processes: 20, not 17 as stated elsewhere in the scorecard

Gap: Minor discrepancy -- the scorecard says "17 PM2 processes" in one section but has 20.

---

### Claim 3: Zero public port exposures (only SSH:22 and Tailscale IP on 3007/443)
**Status: CONFIRMED** (with notes)

Evidence from `ss -tlnp`:
- `0.0.0.0:22` -- SSH (expected)
- `[::]:22` -- SSH IPv6 (expected)
- `100.121.230.28:443` -- nginx on Tailscale IP (acknowledged)
- `100.121.230.28:3007` -- usesend on Tailscale IP (acknowledged)
- `100.121.230.28:33512` -- tailscaled control (internal)
- All other listeners -- `127.0.0.1` only

Zero unexpected 0.0.0.0 listeners. Network exposure posture is sound.

Gap: None significant. The 127.0.0.1 lockdown is legitimate.

---

### Claim 4: All admin panels closed to internet
**Status: CONFIRMED**

Evidence:
- 1panel: 127.0.0.1:8090
- Grafana: 127.0.0.1:3002
- Superset: 127.0.0.1:8088
- Langflow: 127.0.0.1:7860
- Temporal UI: 127.0.0.1:8089
- All dashboards and admin interfaces on 127.0.0.1 only.

Gap: None.

---

### Claim 5: UFW rules reduced 95 -> 64
**Status: PARTIALLY CONFIRMED** (number is wrong but reduction is real)

Evidence:
- Current UFW rule count: **59** (32 IPv4 + 27 IPv6)
- The scorecard claims 64, actual is 59
- This is a 36-rule reduction from 95 (38% reduction)
- The specific number 64 is inaccurate; the actual count is 59 (better, but not what was claimed)

Concern -- Rule [24]: `Anywhere ALLOW IN 172.16.0.0/12` is a very broad allow rule covering 1,048,576 IPs (172.16.0.0 through 172.31.255.255). While Docker uses 172.x ranges, this is wider than necessary. Should be scoped to specific Docker networks.

Gap: Claimed number (64) does not match actual (59). Broad 172.16.0.0/12 allow rule is oversized.

---

### Claim 6: Internal passwords rotated
**Status: CONTRADICTED**

Evidence:
- `command-center` PM2 process env still contains `REDIS_PASSWORD = FRGpassword1!`
- The scorecard claims "Internal DB/Redis passwords rotated" and that `FRGpassword1!` was replaced with unique hex passwords
- Either the rotation did not happen for this process, or the PM2 env was not cleaned after rotation
- If the actual Redis password was changed, command-center is using a stale/now-wrong password

This is a concrete false green -- the old password is still visible in PM2 state.

Gap: PM2 command-center process was missed during secret rotation. Redis password change may not have been propagated to all consumers.

---

### Claim 7: Score A+ (100/100)
**Status: DISPUTED**

Evidence: Multiple claims are contradicted or inaccurate (see above). A 100/100 score requires zero false greens. We have identified at least 4 findings that contradict the claims. An honest score would be significantly lower.

Gap: The score is inflated by flawed verification and missed edge cases.

---

### Claim 8: Zero :latest Docker images (100% Pinned)
**Status: CONTRADICTED**

Evidence:
- 9 running containers use `:latest` tagged images:
  - `prediction-radar-app-worker:latest` (local build, no version)
  - `prediction-radar-app-scheduler:latest` (local build, no version)
  - `prediction-radar-app-api:latest` (local build, no version)
  - `prediction-radar-app-web:latest` (local build, no version)
  - `prediction-radar-app-fincept-terminal:latest` (local build, no version)
  - `prediction-radar-app-dashboard-v2:latest` (local build, no version)
  - `ravynai-opportunity-graph-app:latest` (local build, no version)
  - `netdata/netdata:latest` (used by `netdata` AND `netdata-backup`)
- The scorecard's verification command `docker ps --format '{{.Image}}' | grep ':latest'` returns 0 because `docker ps` OMITS the `:latest` suffix when displaying images. This is a **broken measurement** that produces a false green.
- Proper verification via `docker image inspect` confirms the `:latest` tags exist.

Gap: Verification methodology is flawed. The grep command cannot detect `:latest` when docker ps omits the tag suffix. Netdata and 7 local build images are unpinned.

---

### Claim 9: PM2 jlist has 0 real secrets (5 critical keys eliminated)
**Status: CONTRADICTED**

Evidence:
- `command-center` PM2 process has the following sensitive keys in its env:
  - `DEEPSEEK_API_KEY` -- EXPOSED (value: `sk-4ac726fce2564ce88...`)
  - `ANTHROPIC_AUTH_TOKEN` -- EXPOSED (same value)
  - `HCLOUD_TOKEN` -- EXPOSED (value: `0cIsim41rr5mfo1onucy...`)
  - `LITELLM_MASTER_KEY` -- EXPOSED (value: `sk-4ac726fce2564ce88...`)
  - `REDIS_PASSWORD` -- EXPOSED (value: `FRGpassword1!`)
- The scorecard explicitly states "5 critical keys eliminated from PM2 state" -- ALL FIVE are still present
- The scorecard states "0 real secrets stored (only 13 local service URLs)" -- FALSE for command-center
- Other 18 PM2 processes only have `OPENAI_BASE_URL=http://localhost:4049/v1` which is a local-only URL and not a secret

Gap: The `env -i delete + start` pattern was not applied to the `command-center` process. It still has a polluted PM2 environment from its original start. This is a 5-secret exposure in PM2 jlist.

---

### Claim 10: 20/20 health endpoints passing
**Status: CONTRADICTED**

Evidence:
- `netdata` on 127.0.0.1:19999 returns "Connection reset by peer" (HTTP 000)
- The port IS listening, but the HTTP health check fails
- Other tested endpoints respond correctly:
  - 3000: 200 (open-webui)
  - 3001: 302 (uptime-kuma)
  - 3002: 302 (aiops-grafana)
  - 3010: 200 (docuseal)
  - 5000: 200 (changedetection)
  - 7474: 200 (ecosystem-graph/neo4j)
  - 7860: 200 (langflow)
  - 8007: 401 (ravynai) -- working, requires auth
  - 8085: 200 (webhook-relay)
  - 8088: 302 (superset)
  - 8089: 200 (temporal-ui)
  - 8090: 200 (1panel)
  - 8098: 200 (prediction-radar-web)
  - 8123: 200 (clickhouse)
  - 9090: 200 (prometheus)
  - 3130: 400 (healthchecks)
- Netdata is the only failure among tested endpoints

Gap: Netdata health check fails despite container reporting (healthy). Either the web server within the container is not responding to HTTP, or there is a configuration issue.

---

## ADDITIONAL FINDINGS

### A. UFW Rule [24] -- Overly Broad Allow
Rule [24]: `Anywhere ALLOW IN 172.16.0.0/12` allows traffic from the entire 172.16.0.0/12 range (1M+ IPs). While Docker does use 172.x.x.x addresses, this is wider than necessary. Docker typically uses 172.17.0.0/16. This should be scoped down.

### B. design-agent-svc Restart History
`design-agent-svc` has 2 restarts. While currently stable (pid=2326467), the restart history should be investigated.

### C. System Resources
- Disk: 61G used / 338G total (19%) -- healthy
- RAM: 14G used / 30G total -- healthy (18G buff/cache available)
- Swap: 256K used / 8G -- essentially unused
- Load: 2.74 / 2.02 / 1.38 -- moderate
- Uptime: 1 day, 1 hour -- recently rebooted

### D. Exposed Secrets in PM2 jlist
The command-center process exposes real credential values in PM2 state. Anyone with `pm2 jlist` access can read:
- 1x DeepSeek/Anthropic API key (shared with LITELLM_MASTER_KEY)
- 1x Hetzner Cloud token
- 1x Redis password (old value)

---

## READINESS SCORE: 72/100
**Threshold: YELLOW** (50-79)

### Scoring Breakdown
| Domain | Raw Score | Weight | Weighted |
|--------|-----------|--------|----------|
| PM2 Process Health | 85/100 (19/20 online, but command-center has secrets) | 20% | 17.0 |
| Docker Container Health | 70/100 (42 running, 2 no healthcheck, netdata broken, :latest tags) | 20% | 14.0 |
| Network Exposure and Binds | 95/100 (clean, only SSH + Tailscale) | 20% | 19.0 |
| Cron and Watchdog Liveness | 85/100 (netdata health check fails) | 15% | 12.75 |
| Dashboard Exposure | 100/100 (all on 127.0.0.1) | 10% | 10.0 |
| Gateway Readiness | 80/100 (broad UFW rule, some polish needed) | 10% | 8.0 |
| Rollback Readiness | 85/100 (functional, but netdata down) | 5% | 4.25 |
| **TOTAL** | | | **85.0** |

Adjusted downward for false claims:
- PM2 secrets not cleaned (critical): -5
- :latest images count wrong: -3
- Container count wrong: -2
- Netdata not responding: -3
- **Adjusted Score: 72**

### Blocking Issues (must be resolved before GREEN)
1. **CRITICAL: command-center PM2 process still has 5 real secrets in pm2 jlist.** Apply `env -i delete + start` pattern to clean this process. DEEPSEEK_API_KEY, ANTHROPIC_AUTH_TOKEN, HCLOUD_TOKEN, LITELLM_MASTER_KEY, and REDIS_PASSWORD are exposed.
2. **REDIS_PASSWORD still set to FRGpassword1! in command-center.** Verify if Redis password was actually rotated. If yes, update the PM2 env. If no, complete the rotation.
3. **`:latest` image tags on 9 containers.** Pin `netdata/netdata` to a specific version. Tag local build images with build timestamps or git SHAs.
4. **Netdata health check failure.** Investigate why `curl 127.0.0.1:19999` returns connection reset despite port being in LISTEN state. Fix the broken service.
5. **Fix verification methodology.** The `docker ps --format '{{.Image}}' | grep ':latest'` check is flawed -- it produces false zeros. Replace with `docker inspect`-based check.
6. **Correct container count in documentation.** 42 containers, not 37.
7. **Scope down UFW rule [24].** Replace `172.16.0.0/12` with `172.17.0.0/16` (or actual Docker bridge network).

---

## VERIFICATION COMMANDS USED

```
docker ps -a --format "{{.Names}} {{.Status}} {{.Ports}}"
pm2 jlist | python3 -c "import json,sys; ..."  # parsed all 20 processes
ss -tlnp
ufw status numbered
docker images --format "{{.Repository}}:{{.Tag}}"
docker image inspect <name> --format '{{.RepoTags}}'
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:<port>/
df -h / && free -h && uptime
```

---

*Generated by Zero False Green Auditor. Every claim was tested against live system state.*
*No assumptions. No inherited claims. Direct verification only.*
