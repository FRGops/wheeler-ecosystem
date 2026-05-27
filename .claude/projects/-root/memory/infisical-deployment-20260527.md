---
name: infisical-deployment-20260527
description: Infisical secrets management deployed on COREDB — API-first, machine identities for 50+ autonomous agents, PostgreSQL+Redis backend, SMTP configured (2026-05-27)
metadata:
  type: project
  node_type: memory
  originSessionId: session-20260527-012330
---

# Infisical Deployment — Wheeler Ecosystem Secrets Manager (2026-05-27)

## Why

Three user-proposed options were evaluated and ALL failed for autonomous agent use:

| Option | Verdict | Reason |
|--------|---------|--------|
| LessPass | ❌ | Stateless password generator, no storage, can't store API keys/SSH keys |
| Keeweb | ❌ | GUI-only, no API, no CLI, no headless mode, no multi-user |
| Padloc | ❌ | Zero-trust client-side decryption blocks agents, unmaintained since 2023 |

**Infisical** was selected as the best fit: 27k GitHub stars, MIT license, 97% TypeScript, last release May 26 2026 (yesterday), REST API + Node.js/Python/Go SDKs, first-class machine identities, Docker Compose deployment.

## What Was Deployed

### COREDB (5.78.210.123)

```
/opt/infisical/
├── docker-compose.yml   # Infisical backend + nginx proxy
├── .env                 # Encryption keys, DB/Redis URIs, SMTP
└── (docker volumes are external)
```

**Services:**
- `infisical` (infisical/infisical:latest) — :8089 → :8080, health check at /api/status
- `infisical-nginx` (nginx:alpine) — :8443 → infisical:8080, reverse proxy

**Infrastructure reuse:**
- PostgreSQL: `wheeler-postgres` on `wheeler-core_default` network, database `infisical`
- Redis: `wheeler-redis` on `wheeler-core_default` network
- Network: `wheeler-core_default` (external)

**Database created:** `infisical` on existing `wheeler-postgres`

### API Status Endpoint

`GET /api/status` returns:
```json
{
  "message": "Ok",
  "emailConfigured": true,
  "inviteOnlySignup": true,
  "redisConfigured": true,
  "maxIdentityAccessTokenTTL": 7776000
}
```

### SMTP
Uses SendGrid (same key as usesend). Verified connection to smtp.sendgrid.net:587.

## Admin Setup Required

1. **SSH tunnel:** `ssh -L 8443:127.0.0.1:8443 root@5.78.210.123`
2. **Signup URL:** `http://localhost:8443/admin/signup`
3. Create first admin user (bypasses invite-only for first user)
4. Then create machine identities via API for each agent

## Agent Integration Plan

After admin user is created:

1. **Create organization** "Wheeler Ecosystem" via web UI
2. **Create project per domain** (infra, security, finance, etc.)
3. **Create machine identity per agent role** via API:
   ```
   POST /api/v1/auth/universal-auth/identities
   { "name": "agent-name", "role": "role-name" }
   ```
4. **Install SDKs:** `npm install @infisical/sdk` (Node.js), `pip install infisicalsdk` (Python)
5. **Agent access pattern:**
   ```js
   // Node.js
   import { InfisicalClient } from "@infisical/sdk";
   const client = new InfisicalClient({
     clientId: process.env.INFISICAL_CLIENT_ID,
     clientSecret: process.env.INFISICAL_CLIENT_SECRET,
   });
   const secret = await client.getSecret({ secretName: "DB_PASSWORD", environment: "prod" });
   ```

## Hetzner Firewall Fix Required

**Problem:** Firewall ID 11033456 blocks Tailscale SSH (100.118.166.117:22 → connection refused). SSH works only via public IP (5.78.210.123:22).

**Fix needed:** Add rule to Hetzner Cloud Firewall 11033456:
- Direction: inbound
- Protocol: TCP
- Port: 22
- Source: 100.64.0.0/10 (Tailscale CGNAT range)

**Cannot execute:** HCLOUD_TOKEN not persisted on AIOPS. Need token or Hetzner Cloud Console access.

## Deployment Configs

Saved at `/root/deployment-engine/services/infisical/`:
- `docker-compose.yml` — service definitions
- `nginx.conf` — reverse proxy config
- `.env.template` — environment variable template (without secrets)
