---
name: cap-drop-patterns
description: "Common failures when applying cap_drop ALL to containers — s6-overlay, nginx, postgres"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cf1e5c0f-ee3a-43ab-aadd-f99343ec85e0
---

Three patterns where `cap_drop: ALL` silently breaks containers:

1. **LinuxServer/s6-overlay images** (healthchecks, uptime-kuma): Need `cap_add: [SETGID, SETUID]`. Error: `s6-applyuidgid: fatal: unable to set supplementary group list`. These images use PUID/PGID to drop privileges internally — s6-overlay's `setpriv setgroups()` requires these caps.

2. **nginx entrypoint**: Needs `cap_add: [CHOWN, SETGID, SETUID]`. Error: `chown("/var/cache/nginx/client_temp", 101) failed (1: Operation not permitted)`. The nginx entrypoint chowns temp directories to UID 101 before starting workers.

3. **PostgreSQL Alpine**: Needs `cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID]`. Alpine-based postgres uses UID 70, not 999.

**Why:** cap_drop ALL is applied before entrypoint scripts run. Entrypoints that chown, setuid, or manipulate groups fail silently. Always test container after adding cap_drop ALL.

**How to apply:** After adding cap_drop ALL to any container, verify it's healthy. If crashing, check logs for "Operation not permitted" and add minimal caps back.
