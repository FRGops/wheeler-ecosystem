---
name: infisical-agentic-secrets-platform-20260527
description: Infisical fully deployed, wired, and agent-autonomous — admin user created, machine identity with access token generated, ready for 50+ agents (2026-05-27)
metadata:
  type: project
  node_type: memory
  originSessionId: session-20260527-012330
---

# Infisical — Fully Agentic Secrets Platform (2026-05-27)

## Why

Three user-proposed options were evaluated and ALL failed for autonomous agent use:

| Option | Verdict | Reason |
|--------|---------|--------|
| LessPass | ❌ | Stateless password generator, no storage |
| Keeweb | ❌ | GUI-only, no API, no multi-user |
| Padloc | ❌ | Client-side decryption blocks agents, unmaintained since 2023 |

**Infisical** (27k stars, MIT, active) was selected: REST API, Node.js/Python SDKs, first-class machine identities, Docker Compose, reuses existing PostgreSQL + Redis.

## What Was Deployed

### COREDB (5.78.210.123)

```
/opt/infisical/
├── docker-compose.yml   # Infisical backend + nginx proxy
├── .env                 # Encryption keys, DB/Redis URIs, SMTP
```

**Services:**
- `infisical` (infisical/infisical:latest, v0.160.7) — :8089→:8080, health check at /api/status
- `infisical-nginx` (nginx:alpine) — :8443→infisical:8080, reverse proxy

**Infrastructure:**
- PostgreSQL: wheeler-postgres, database `infisical`
- Redis: wheeler-redis
- Network: wheeler-core_default
- SMTP: SendGrid (same key as usesend, verified working)

### Admin Account
- Email: ops@fundsrecoverygroup.com
- Server Console: http://127.0.0.1:8443/admin

### Organization
- Name: Admin Org
- ID: f284d059-879e-42e6-8a93-b938cc291531

### Machine Identity (1 of many)
- **wheeler-infra-agent**
  - Identity ID: a561a9f2-6f10-4168-976c-105580665b52
  - Auth method: Token Auth
  - Token expires: 2026-06-26 (30 days)
  - Access token saved at: `/root/.claude/.infisical-credentials.json`

## Agent Integration (How-to)

### Node.js agents
```js
// npm install @infisical/sdk
import { InfisicalClient } from "@infisical/sdk";
const client = new InfisicalClient({
  accessToken: process.env.INFISICAL_TOKEN,  // JWT from machine identity
  siteUrl: "http://infisical:8080",
});
const secret = await client.getSecret({ 
  secretName: "DB_PASSWORD", 
  environment: "prod",
  projectId: "<project-id>"
});
```

### Python agents
```python
# pip install infisicalsdk
from infisical import InfisicalClient
client = InfisicalClient(
    access_token=os.environ["INFISICAL_TOKEN"],
    site_url="http://infisical:8080",
)
secret = client.get_secret(secret_name="DB_PASSWORD", environment="prod")
```

### Direct API (curl/bash)
```bash
curl -H "Authorization: Bearer $INFISICAL_TOKEN" \
  http://infisical:8080/api/v3/secrets/raw/{secretName}
```

## Remaining Setup

1. **Rename org**: "Admin Org" → "Wheeler Ecosystem" in Server Console
2. **Create projects**: infra, security, finance, growth, etc.
3. **Add secrets**: Migrate existing PostgreSQL/Redis/MinIO passwords, API keys
4. **Create more machine identities**: One per agent role (wheeler-deploy-agent, wheeler-security-agent, etc.)
5. **Install SDKs** on agent services
6. **Rotate tokens**: 30-day token TTL — set up cron auto-rotation

## Hetzner Firewall Fix Required

Firewall ID 11033456 blocks Tailscale SSH (100.118.166.117:22). Need rule:
- Direction: inbound, Protocol: TCP, Port: 22, Source: 100.64.0.0/10
- HCLOUD_TOKEN not persisted — needs manual console access or token injection

## Deployment Configs

Saved at `/root/deployment-engine/services/infisical/`:
- `docker-compose.yml`, `nginx.conf`, `.env.template`
- Machine identity credentials: `/root/.claude/.infisical-credentials.json` (chmod 600)
