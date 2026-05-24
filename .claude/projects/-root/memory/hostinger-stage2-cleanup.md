---
name: hostinger-stage2-cleanup
description: "Hostinger Stage 2 exposure cleanup executed 2026-05-24 — UFW rules reduced from 95→64, 8 admin panels closed to internet"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5dc7b211-2690-4ac6-bd8b-d9f225f194f0
---

Hostinger Stage 2 exposure cleanup executed on 2026-05-24.

**Before:** 95 UFW rules, 8 admin panels exposed to internet via UFW rule-ordering contradiction (tailscale0 bindings overridden by later Anywhere ALLOW rules).

**After:** 64 UFW rules, only SSH/HTTP/HTTPS publicly reachable, 19 ports restricted to Tailscale-only.

**Changes made:**
- Deleted 10 Anywhere ALLOW rules (Phase 1) — 8 admin panels dark
- Deleted 12 duplicate 100.64.0.0/10 rules (Phase 2) 
- Deleted 7 stale rules (ports 5001, 4000, 3000)
- Added tailscale0 ALLOW + explicit DENY for temporal-ui (8089) and usesend (8005)
- Fixed node_exporter binding: *:9100 → 127.0.0.1:9100
- Docker containers already on 127.0.0.1 (no changes needed)
- SSH unchanged: key-only, LIMIT rate-limited, public

**Why:** Audit revealed UFW contradiction — tailscale0 interface-bound rules intended to restrict admin panels but later Anywhere ALLOW rules overrode them (first-match-wins). Docker 0.0.0.0 bindings also created parallel bypass of correctly-configured nginx Tailscale-only gateway.

**How to apply:** UFW is now clean. Future rule changes should follow the pattern: tailscale0 ALLOW for internal services, explicit DENY Anywhere for defense-in-depth, minimal public surface (22/80/443 only).

**Deliverables:** /root/HOSTINGER_PUBLIC_SURFACE.md, /root/HOSTINGER_UFW_AUDIT.md, /root/HOSTINGER_INTERNAL_SERVICES.md, /root/HOSTINGER_STAGE2_CLEANUP_PLAN.md
