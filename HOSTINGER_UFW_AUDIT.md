# Hostinger UFW Firewall Audit
**Server:** wheeler-aiops-01 | **Date:** 2026-05-24 | **Total Rules:** 95 (59 IPv4 + 36 IPv6)

---

## 1. Global Configuration

| Property | Value |
|----------|-------|
| Status | **active** |
| Default Incoming | **deny** (good) |
| Default Outgoing | **allow** |
| Default Routed | **deny** |
| Logging | on (low) |

---

## 2. The Structural Contradiction

UFW uses **first-match-wins**. The current rule ordering creates a fundamental problem:

```
Rule 4-17:   ALLOW <port> on tailscale0  ← "admin should be TS-only"
Rule 18-29:  ALLOW <port> from 100.64.0.0/10  ← redundant duplicates
Rule 30-41:  ALLOW <port> from Anywhere  ← OVERRIDES the tailscale0 intent!
```

**Result:** For ports 8090, 3002, 8088, 5000, 3130, 3001, 19999, and 8098 — the earlier `tailscale0` interface binding is overridden by the later `Anywhere` rule. The internet CAN reach these.

Only ports **9000 (ClickHouse native)** and **9090 (Prometheus)** are properly protected because rules 36 and 40 explicitly DENY from Anywhere before the traffic reaches any permissive rule.

---

## 3. Rule-by-Rule Classification

### Group A: tailscale0 Interface-Bound (Rules 4-17) — GOOD INTENT

| Rule | Port | Service | Status |
|------|------|---------|--------|
| 4 | 19999 | netdata | Overridden by #39 |
| 5 | 3001 | uptime-kuma | Overridden by #38 |
| 6 | 3002 | grafana | Overridden by #33 |
| 7 | 5000 | changedetection | Overridden by #34 |
| 8 | 8088 | superset | Overridden by #32 |
| 9 | 8098 | prediction-radar | Overridden by #30 |
| 10 | 8007 | surplusai-scraper-agent | Overridden by #31 |
| 11 | 8123 | clickhouse HTTP | **SAFE** (no Anywhere override) |
| 12 | 9000 | clickhouse native | **SAFE** (DENY at #36) |
| 13 | 5001 | **NO SERVICE** | **STALE** (nothing listens) |
| 14 | 8090 | 1panel | Overridden by #41 |
| 15 | 9090 | prometheus | **SAFE** (DENY at #40) |
| 16 | 3130 | healthchecks | Overridden by #35 |
| 17 | 5434 | postgres | **SAFE** (no Anywhere override) |

### Group B: 100.64.0.0/10 Subnet (Rules 18-29) — ALL DUPLICATE

Every rule in this group duplicates protection already provided by Group A (tailscale0) or Group C (Anywhere). **All 12 rules can be deleted with zero change to effective policy.**

### Group C: Anywhere ALLOW (Rules 30-41) — THE PROBLEM

| Rule | Port | Service | Severity | Action |
|------|------|---------|----------|--------|
| 30 | 8098 | prediction-radar | MEDIUM | Delete (keep tailscale0 #9) |
| 31 | 8007 | surplusai-scraper-agent | HIGH | Delete (keep tailscale0 #10) |
| 32 | 8088 | superset | HIGH | Delete (keep tailscale0 #8) |
| 33 | 3002 | grafana | HIGH | Delete (keep tailscale0 #6) |
| 34 | 5000 | changedetection | MEDIUM | Delete (keep tailscale0 #7) |
| 35 | 3130 | healthchecks | MEDIUM | Delete (keep tailscale0 #16) |
| 36 | 9000 | clickhouse native | **KEEP** | Explicit DENY — good |
| 37 | 5001 | **NO SERVICE** | STALE | Delete |
| 38 | 3001 | uptime-kuma | HIGH | Delete (keep tailscale0 #5) |
| 39 | 19999 | netdata | HIGH | Delete (keep tailscale0 #4) |
| 40 | 9090 | prometheus | **KEEP** | Explicit DENY — good |
| 41 | 8090 | 1panel | **CRITICAL** | Delete (keep tailscale0 #14) |

### Group D: Infrastructure (Rules 42-59)

| Rule | Port | Source | Classification |
|------|------|--------|----------------|
| 42-43 | 9091 | docker0/172.17.0.0/16 | ADMIN — health exporter, acceptable |
| 44 | 5432 | 100.64.0.0/10 | ADMIN — PostgreSQL Tailscale access |
| 45 | 5433 | 100.64.0.0/10 | ADMIN — standby PG Tailscale |
| 46 | 5434 | 100.64.0.0/10 | DUPLICATE of #17 |
| 47 | 6379 | 100.64.0.0/10 | ADMIN — Redis Tailscale access |
| 48 | 22 | Anywhere (LIMIT) | PUBLIC — SSH rate-limited |
| 49 | 22 | 100.64.0.0/10 | DUPLICATE of #48 |
| 50 | 3000 | 100.64.0.0/10 | MISCONFIGURED — open-webui on 127.0.0.1 |
| 51 | 4000 | 100.64.0.0/10 | **STALE** — nothing listens |
| 52 | Any | 172.16.0.0/12 | OVERLY BROAD |
| 53 | Any | 10.0.0.0/8 | OVERLY BROAD |
| 54 | 5433 | Anywhere (DENY) | KEEP — properly restricted |
| 55 | 5433 | tailscale0 | KEEP |
| 56 | 8103 | tailscale0 | KEEP |
| 57 | 3003 | tailscale0 | KEEP |
| 58 | 3007 | tailscale0 | KEEP |
| 59 | 5433 | 10.0.0.0/16 | DUPLICATE of #55 |

### Group E: IPv6 Mirror (Rules 60-95) — ALL DUPLICATE

Exact IPv6 mirrors of rules 1-59. If IPv6 is not active on the public interface, all 36 rules are dead weight. If it IS active, the same structural contradiction applies.

---

## 4. Stale Rules (No Backend Service)

| Rule(s) | Port | Detail |
|---------|------|--------|
| 13, 25, 37, 72, 84 | **5001** | Nothing listens on this port |
| 51 | **4000** | Nothing listens on this port |
| 50 | **3000** | open-webui binds 127.0.0.1 only; rule targets Tailscale CIDR but traffic to 0.0.0.0:3000 won't reach it |

---

## 5. Summary Statistics

| Metric | Count |
|--------|-------|
| Total rules | 95 |
| IPv4 rules | 59 |
| IPv6 rules | 36 |
| Intentional public rules (22, 80) | 2 |
| Stale rules (no service) | 7 |
| Duplicate/redundant rules | ~20 |
| Overly broad rules (172.16/12, 10/8) | 2 |
| Admin panels exposed to internet | **8** |
| Properly restricted ports | ~15 |

---

## 6. Proposed Rule Reduction

**Before:** 95 rules
**After cleanup:** ~40 rules (removing all duplicates, stale entries, and internet-exposed admin rules)

The core firewall intent is clear from Group A: admin/monitoring on `tailscale0` only. Groups B and C undermine that intent through redundancy and contradiction. Fixing this is straightforward: delete Groups B and C (keeping the two DENY rules for 9000 and 9090), then remove the stale and IPv6 rules.
