---
name: aiops-remediation-20260524
description: "AI Ops Stage 2 discovery + full remediation — all Docker containers rebound to 127.0.0.1, Langflow auth fixed, nginx hardened with universal basic auth + rate limiting (2026-05-24)"
metadata: 
  node_type: memory
  type: project
  originSessionId: d54f123c-d442-4337-b125-418f1fa540ae
---

Full AI Ops security hardening completed 2026-05-24.

**Why:** Stage 2 discovery revealed 17 wildcard Docker binds, Langflow with AUTO_LOGIN=true (no auth), usesend CRM on plain HTTP, and multiple admin panels exposed without TLS. All required immediate remediation.

**What was fixed:**
- 26 Docker containers rebound from 0.0.0.0 to 127.0.0.1 (compose files already had correct bindings, containers were stale)
- Langflow: AUTO_LOGIN=false, superuser password set (user hardened to 1000:1000, needed chown on data dir)
- usesend CRM: moved from host networking to bridge, 127.0.0.1:3007, TLS via crm.aiops nginx vhost
- node_exporter: --web.listen-address changed from :9100 to 127.0.0.1:9100
- ravyn-agent-svc: HOST=127.0.0.1 added to ecosystem.config.js
- nginx gateway: TLSv1.0/1.1 removed, universal basic auth (htpasswd), rate limiting 30r/m, crm.aiops + clickhouse.aiops vhosts added
- Stale UFW rules for ports 3003, 5001 removed
- PM2 state saved

**How to apply:** All changes were live-applied. PM2 state saved for reboot persistence. Docker compose files at /opt/apps/*/docker-compose.yml are the source of truth for container bindings.

**Verification:** Only SSH (22) remains on 0.0.0.0. All other services require basic auth via nginx on 100.121.230.28:443.
