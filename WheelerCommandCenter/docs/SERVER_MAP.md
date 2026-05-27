# Wheeler Server Map

## Ecosystem Servers

### Mac — CEO Command Center
- **Role:** Local dev, orchestration, operator console
- **Hostname:** local
- **SSH:** local
- **IP:** TODO_DISCOVER (Tailscale)
- **Allowed:** Command center, dev, repos, AI model launcher
- **Forbidden:** Production DB, critical public hosting

### Hostinger — Public Production Server
- **Role:** Public-facing revenue applications
- **SSH Alias:** `ssh hostinger`
- **IP:** TODO_HOSTINGER_PUBLIC_IP (public), TODO_HOSTINGER_TAILSCALE_IP (tailscale)
- **Allowed:** FRG website, public portals, revenue funnels
- **Forbidden:** Heavy AI builds, private core database
- **Domains:** fundsrecoverygroup.com, www.fundsrecoverygroup.com

### Hetzner CPX51 — AIops Control Plane
- **Role:** Internal AIops, build automation, agent fleet
- **SSH Alias:** `ssh hetzner`
- **IP:** 5.78.140.118 (public), TODO_HETZNER_TAILSCALE_IP (tailscale)
- **Allowed:** AIops, build workers, agents, scrapers, automation
- **Forbidden:** Public database exposure
- **Services:** Docker, PM2, Nginx, Prometheus, Grafana, LiteLLM, Uptime Kuma, Netdata

### CoreDB — Private Data Layer
- **Role:** Private databases, storage, memory/vector stores
- **SSH Alias:** `ssh coredb`
- **IP:** TODO_COREDB_PUBLIC_IP (public), TODO_COREDB_TAILSCALE_IP (tailscale)
- **Allowed:** PostgreSQL, Redis, backups, vector stores
- **Forbidden:** Public websites, unprotected admin panels

## Connectivity

```
Mac ──Tailscale──> Hostinger
Mac ──Tailscale──> Hetzner
Mac ──Tailscale──> CoreDB
Hostinger <──Tailscale──> Hetzner
Hostinger <──Tailscale──> CoreDB
Hetzner <──Tailscale──> CoreDB
```

## Discovery Commands

```bash
# Find server public IP (run on each server)
curl -s https://api.ipify.org

# Find Tailscale IPs (run anywhere with Tailscale)
tailscale status

# Test SSH connectivity
wheeler ssh hostinger   # or hetzner, coredb

# Check server health
wheeler health
```
