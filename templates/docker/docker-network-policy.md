# Wheeler — Docker Network Segmentation Policy

> **Classification**: INTERNAL — Platform Engineering
> **Effective date**: 2026-05-23
> **Applies to**: All Wheeler Docker hosts (EDGE, AIOPS, COREDB)
>
> This document defines the network segmentation design, which services can
> communicate with each other, firewall implications, internal vs external
> networks, and container DNS patterns for the Wheeler 3-server topology.

---

## Table of Contents

1. [Network Architecture Overview](#1-network-architecture-overview)
2. [Standard Network Definitions](#2-standard-network-definitions)
3. [Communication Matrix](#3-communication-matrix)
4. [Firewall Implications](#4-firewall-implications)
5. [Internal vs External Networks](#5-internal-vs-external-networks)
6. [Container DNS Patterns](#6-container-dns-patterns)
7. [Network Security Rules](#7-network-security-rules)
8. [Troubleshooting Network Issues](#8-troubleshooting-network-issues)

---

## 1. Network Architecture Overview

### 1.1 Three-Layer Network Model

```
┌────────────────────────────────────────────────────────────────────┐
│                        PUBLIC INTERNET                             │
│                               │                                    │
│                               ▼                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  EDGE NODE (Hostinger / 187.77.148.88)                      │  │
│  │                                                              │  │
│  │  ┌──────────┐   ┌──────────┐   ┌────────────────────────┐   │  │
│  │  │ Traefik  │   │  Nginx   │   │  traefik-public        │   │  │
│  │  │ (443)    │   │  (80)    │   │  (Docker network)       │   │  │
│  │  └────┬─────┘   └──────────┘   │                         │   │  │
│  │       │                        │  Frontend dashboards     │   │  │
│  │       │  ┌─────────────────────┤  Static sites            │   │  │
│  │       │  │                     └────────────────────────┘   │  │
│  │       │  │                                                  │  │
│  │       │  │  ┌────────────────────────────────────────────┐  │  │
│  │       │  │  │  edge-internal (Docker network)            │  │  │
│  │       │  │  │  Edge-local services                       │  │  │
│  │       │  │  └────────────────────────────────────────────┘  │  │
│  └───────┼──┼──────────────────────────────────────────────────┘  │
│          │  │                                                     │
│   ┌──────┼──┼──────────────────────────────────────────────────┐  │
│   │Tailscale (100.x.x.x mesh)                                  │  │
│   │      │  │                                                  │  │
│   │      │  └──────────────┬────────────────────┐              │  │
│   │      │                 │                    │              │  │
│   └──────┼─────────────────┼────────────────────┼──────────────┘  │
│          │                 │                    │                 │
│          ▼                 ▼                    ▼                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │  AIOPS       │  │  COREDB      │  │  (future)    │           │
│  │  5.78.140.118│  │  5.78.210.123│  │              │           │
│  │              │  │              │  │              │           │
│  │ traefik-pub  │  │ database     │  │              │           │
│  │ backend      │  │ monitoring   │  │              │           │
│  │ monitoring   │  │              │  │              │           │
│  │ aiops-int    │  │              │  │              │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
└────────────────────────────────────────────────────────────────────┘
```

### 1.2 Network Tiers

| Tier | Name | Scope | Access Control |
|------|------|-------|---------------|
| **Tier 0** | Public Internet | Global | Rate-limited, WAF, DDoS protection |
| **Tier 1** | traefik-public | Per-node Docker | Traefik routes only; TLS termination |
| **Tier 2** | backend / aiops-internal | Per-node Docker | Internal service-to-service; no internet route |
| **Tier 3** | database | Per-node Docker | Strict database-only; internal only |
| **Tier 4** | Tailscale mesh | Multi-node | WireGuard encrypted; 100.x.x.x addressing |

---

## 2. Standard Network Definitions

### 2.1 EDGE Node Networks

```yaml
# /opt/wheeler/infrastructure/edge/compose/docker-compose.yml
networks:
  # TIER 1: Public-facing services (Traefik routes)
  traefik-public:
    external: true
    name: traefik-public
    # Connected services: Traefik, Nginx, frontend dashboards

  # TIER 2: Edge-local internal services
  edge-internal:
    driver: bridge
    internal: false
    ipam:
      config:
        - subnet: "172.31.0.0/20"
    # Connected services: Change detection, healthchecks, monitoring agents
```

### 2.2 AIOPS Node Networks

```yaml
# /opt/wheeler/infrastructure/aiops/compose/docker-compose.yml
networks:
  # TIER 1: Services exposed through EDGE Traefik
  traefik-public:
    external: true
    name: traefik-public
    # Connected: Langflow, Superset, RavynAI, Grafana, Uptime Kuma

  # TIER 2: Internal AIOPS service-to-service communication
  aiops-internal:
    driver: bridge
    internal: false
    ipam:
      config:
        - subnet: "172.21.0.0/20"
    # Connected: All AIOPS Docker services, PM2 services (via host network)

  # TIER 2 (isolated): Service-specific internal networks
  langflow-internal:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: "172.22.1.0/24"
    # Connected: Langflow and its sidecar dependencies only

  analytics-internal:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: "172.22.2.0/24"
    # Connected: Superset and its dependencies

  ravynai-internal:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: "172.22.3.0/24"
    # Connected: RavynAI app and its PostgreSQL

  predictionradar-internal:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: "172.22.4.0/24"
    # Connected: Prediction Radar and its PostgreSQL/Redis

  # TIER 3: Monitoring (observability stack)
  monitoring:
    external: true
    name: monitoring
    # Connected: Prometheus, Loki, Grafana, Promtail, node-exporter, cadvisor
```

### 2.3 COREDB Node Networks

```yaml
# /opt/wheeler/infrastructure/coredb/compose/docker-compose.yml
networks:
  # TIER 3: Database-only network (strict isolation)
  database:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: "172.23.0.0/20"
    # Connected: PostgreSQL, Redis, MinIO, pgBackRest, vector DBs

  # TIER 3: Monitoring
  monitoring:
    external: true
    name: monitoring
    # Connected: Prometheus exporters, node-exporter, cadvisor
```

### 2.4 Network Driver Comparison

| Feature | bridge (default) | overlay | macvlan | host |
|---------|-----------------|---------|---------|------|
| **Scope** | Single host | Multi-host (Swarm) | Single host | Single host |
| **Isolation** | Good (NAT) | Good (VXLAN) | Minimal | None |
| **DNS** | Built-in | Built-in | External | Host DNS |
| **Performance** | Good (slight NAT overhead) | Moderate (encryption) | Best (direct L2) | Best (no isolation) |
| **Wheeler use** | Primary driver | Future (Swarm) | Not used | PM2 services only |

---

## 3. Communication Matrix

### 3.1 Who Can Talk to Whom

```
                    TO →
FROM ↓              EDGE          AIOPS         COREDB        INTERNET      TAILSCALE
                    traefik-pub   traefik-pub   database      (external)    (100.x)
                    edge-internal aiops-internal monitoring
                                  monitoring

EDGE traefik-public  ✓            ✗             ✗             ✓(via Traefik) ✓
EDGE edge-internal   ✓            ✓(Tailscale)  ✓(Tailscale)  ✗             ✓

AIOPS traefik-public ✗            ✓             ✗             ✗             ✓
AIOPS aiops-internal ✗            ✓             ✓(Tailscale)  ✓(outbound)   ✓
AIOPS monitoring     ✗            ✓             ✓(Tailscale)  ✗             ✓

COREDB database      ✗            ✗             ✓             ✗             ✓
COREDB monitoring    ✗            ✗             ✓             ✗             ✓

INTERNET             ✓(443 only)  ✗             ✗             —             ✗
TAILSCALE             ✓           ✓             ✓             ✗             ✓
```

### 3.2 Specific Service Communication Paths

| Source Service | Destination | Path | Protocol | Port |
|---------------|-------------|------|----------|------|
| EDGE Traefik | AIOPS PM2 apps | Tailscale | HTTP/HTTPS | app ports (8082, 8100, etc.) |
| EDGE Traefik | AIOPS Docker apps | Tailscale | HTTP/HTTPS | app ports |
| AIOPS PM2 apps | COREDB PostgreSQL | Tailscale | PostgreSQL | 5432 |
| AIOPS PM2 apps | COREDB Redis | Tailscale | Redis | 6379 |
| AIOPS Docker apps | COREDB PostgreSQL | Tailscale | PostgreSQL | 5432 |
| AIOPS Docker apps | COREDB MinIO | Tailscale | S3 HTTP | 9000 |
| AIOPS LiteLLM | External AI APIs | Direct (NAT) | HTTPS | 443 |
| COREDB PostgreSQL | External | None | — | — |
| COREDB MinIO | External (backup sync) | Tailscale → EDGE → NAT | S3 HTTPS | 443 |
| Prometheus | All node exporters | Tailscale | HTTP | 9100 |
| Promtail (all nodes) | COREDB Loki | Tailscale | gRPC/HTTP | 3100 |

---

## 4. Firewall Implications

### 4.1 Per-Node Firewall Rules

#### EDGE Node (Hostinger / 187.77.148.88)

```bash
# Public-facing ports
ufw allow 80/tcp        # HTTP (Nginx)
ufw allow 443/tcp       # HTTPS (Traefik)

# Tailscale mesh (already handled by Tailscale)
# No explicit rules needed — Tailscale manages its own firewall

# Block all other inbound from public internet
ufw default deny incoming
ufw allow out 80,443/tcp  # Allow outbound HTTP/HTTPS for updates
```

#### AIOPS Node (Hetzner / 5.78.140.118)

```bash
# No public-facing ports — all traffic comes through Tailscale
ufw default deny incoming
ufw allow out 80,443/tcp   # Allow AI API calls, package updates
ufw allow out 53/udp       # DNS resolution

# Tailscale manages inter-node communication
# No explicit port rules needed for Tailscale
```

#### COREDB Node (Hetzner / 5.78.210.123)

```bash
# No public-facing ports — all traffic through Tailscale
ufw default deny incoming
ufw allow out 80,443/tcp   # Allow outbound for backup sync, updates
ufw allow out 53/udp       # DNS resolution

# Tailscale manages inter-node communication
```

### 4.2 Docker Network Firewall Behavior

Docker manipulates iptables rules directly.  UFW rules may be bypassed by
Docker's iptables rules.  Important considerations:

1. **Docker publishes ports to 0.0.0.0 by default**: When you use
   `ports: - "8080:8080"` (without a bind address), Docker adds iptables
   rules that accept traffic from ALL interfaces, including the public
   internet.  This bypasses UFW.

   **Mitigation**: Always bind to loopback:
   ```yaml
   ports:
     - "127.0.0.1:8080:8080"   # Only accessible from localhost
   ```

2. **Docker networks are NAT'ted**: Containers on bridge networks access
   the internet via NAT (masquerade).  This is fine for outbound access
   but means containers are not directly reachable from outside Docker.

3. **`internal: true` networks**: Containers on internal networks cannot
   access the internet at all.  Use for databases, Redis, and services that
   should never make outbound connections.

4. **iptables persistence**: Docker's iptables rules are recreated on Docker
   daemon restart.  Do not manually manage iptables rules for Docker networks.

### 4.3 Verifying Firewall Configuration

```bash
# Check UFW status
ufw status verbose

# Check Docker iptables rules
iptables -L DOCKER -n -v

# Check which ports are listening
ss -tlnp

# Verify a port is NOT publicly accessible
# Run from an external machine:
nc -zv 187.77.148.88 8082   # Should fail if properly firewalled
```

---

## 5. Internal vs External Networks

### 5.1 Definition

| Attribute | Internal Network | External Network |
|-----------|-----------------|-----------------|
| **Internet access** | No (container cannot reach internet) | Yes (container can reach internet) |
| **Host access** | Yes (via published ports) | Yes (via published ports) |
| **Docker DNS** | Yes | Yes |
| **Inter-container** | Yes (on same network) | Yes (on same network) |
| **Docker Compose flag** | `internal: true` | `internal: false` (default) |
| **Use case** | Databases, caches, internal-only services | APIs, web UIs, services that call external APIs |

### 5.2 Wheeler Internal Networks

These networks have `internal: true` and are used ONLY for service-to-service
communication within a strictly bounded scope:

| Network | Services | Internet Access |
|---------|----------|----------------|
| `database` (COREDB) | PostgreSQL, Redis, MinIO | No |
| `langflow-internal` | Langflow + sidecar DB | No |
| `analytics-internal` | Superset + its PostgreSQL | No |
| `ravynai-internal` | RavynAI + its PostgreSQL | No |
| `predictionradar-internal` | Prediction Radar + PG + Redis | No |
| `monitoring` (all nodes) | Prometheus, Grafana, Loki | No |

### 5.3 Wheeler External Networks

These networks have `internal: false` and allow containers to reach the
internet (for API calls, package updates, etc.):

| Network | Services | Internet Access |
|---------|----------|----------------|
| `traefik-public` (EDGE) | Traefik, Nginx, frontend UIs | Yes (for TLS, outbound) |
| `aiops-internal` | General AIOPS services | Yes (for AI API calls, webhooks) |
| `edge-internal` | EDGE-local services | Yes (for outbound webhooks, monitoring) |

### 5.4 When to Use Internal Networks

Use `internal: true` when:
- The service NEVER needs to reach the internet.
- The service handles sensitive data (databases, caches, secrets stores).
- The service is a sidecar that only talks to its parent service.
- You want defense-in-depth: even if the container is compromised, it cannot
  exfiltrate data to the internet.

DO NOT use `internal: true` when:
- The service calls external APIs (LiteLLM, OpenClaw, Voice Agent).
- The service needs to download models or packages at runtime.
- The service sends webhooks or notifications to external services.
- The service needs DNS resolution for public hostnames.

---

## 6. Container DNS Patterns

### 6.1 Docker DNS Resolution

Docker provides built-in DNS resolution for containers:

1. **Service name resolution**: On a user-defined bridge network, containers
   can resolve each other by service name or container name.

   ```bash
   # From container "my-app" on network "backend":
   ping my-database    # Resolves to the "my-database" container IP
   ping my-redis       # Resolves to the "my-redis" container IP
   ```

2. **Network-scoped resolution**: DNS names are scoped to the network.
   A container on `network-a` cannot resolve names on `network-b`.

3. **Custom DNS servers**: Containers use Docker's embedded DNS server
   (127.0.0.11) by default, which forwards to the host's DNS servers.

### 6.2 Wheeler DNS Configuration

```yaml
# In docker-compose.yml, specify custom DNS for containers that need it:
services:
  my-service:
    dns:
      - 127.0.0.11          # Docker's embedded DNS (internal resolution)
      - 1.1.1.1             # Cloudflare (external resolution fallback)
      - 8.8.8.8             # Google (tertiary fallback)
    dns_search:
      - wheeler.ai           # Search domain for short hostnames
```

### 6.3 Cross-Host DNS (Tailscale)

Docker DNS works within a single Docker host.  For cross-host communication
(EDGE to AIOPS, AIOPS to COREDB), use Tailscale IPs or Tailscale MagicDNS:

```bash
# Option 1: Tailscale IP (hardcoded, always works)
DATABASE_URL="postgresql://wheeler:password@100.118.166.117:5432/wheeler_core"

# Option 2: Tailscale MagicDNS hostname (requires Tailscale MagicDNS enabled)
DATABASE_URL="postgresql://wheeler:password@wheeler-coredb:5432/wheeler_core"

# Option 3: /etc/hosts entry (manual, useful for testing)
# Add to container via extra_hosts:
extra_hosts:
  - "coredb:100.118.166.117"
  - "aiops:100.121.230.28"
  - "edge:100.110.48.189"
```

For Wheeler, COREDB connectivity is handled via Tailscale IPs stored as
environment variables.  This is the most reliable pattern because:
- MagicDNS requires enabling in the Tailscale admin console.
- MagicDNS may not work in all Docker networking modes.
- IP addresses are stable (Tailscale assigns persistent IPs).

### 6.4 DNS Troubleshooting

```bash
# From inside a container, test DNS resolution:
docker exec <container> nslookup <hostname>
docker exec <container> ping -c 1 <hostname>
docker exec <container> curl -v http://<hostname>:<port>/health

# Test Docker DNS from host:
docker run --rm --network <network> alpine nslookup <service-name>

# Check Docker DNS server is responding:
docker exec <container> cat /etc/resolv.conf
# Should show: nameserver 127.0.0.11
```

---

## 7. Network Security Rules

### 7.1 Principle of Least Privilege

Apply these rules when connecting containers to networks:

1. **Connect to the minimum number of networks**: A service on 3 networks
   has 3 possible attack surfaces.  A service on 1 network has 1.

2. **Use `internal: true` for data stores**: Databases, caches, and object
   stores should never have internet access.

3. **Separate public and private traffic**: A service that is both
   internet-facing AND database-connected should use two networks:
   - `traefik-public` (for Traefik routing).
   - `backend` or service-specific internal network (for DB access).

4. **Isolate per-service databases**: If a service has its own sidecar
   database (not the shared COREDB), put them on a dedicated internal network
   that only those two containers share.

### 7.2 Network Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| All services on one network | Compromise of any service exposes all | Use tiered networks |
| Ports bound to 0.0.0.0 | Bypasses host firewall | Bind to 127.0.0.1 |
| `network_mode: host` | No isolation | Use bridge networks |
| Database on `traefik-public` | Database reachable from internet | Move to `database` network |
| `internal: false` for databases | Database can phone home | Set `internal: true` |
| Hardcoded IPs in app config | Breaks on container restart | Use service names or env vars |

### 7.3 Network Audit Script

```bash
#!/bin/bash
# Audit Docker networks for security policy compliance

echo "=== Docker Network Security Audit ==="

# Check for containers on too many networks
docker inspect $(docker ps -q) | jq -r '
  .[] | select((.NetworkSettings.Networks | length) > 3) |
  "WARN: \(.Name) is on \(.NetworkSettings.Networks | length) networks: \(.NetworkSettings.Networks | keys | join(", "))"'

# Check for ports bound to 0.0.0.0
docker ps --format '{{.Names}} {{.Ports}}' | grep "0.0.0.0" | while read line; do
  echo "WARN: Container with public port binding: $line"
done

# Check for host network mode
docker ps --format '{{.Names}} {{.Networks}}' | grep host | while read line; do
  echo "CRITICAL: Container using host network: $line"
done

echo "=== Audit Complete ==="
```

---

## 8. Troubleshooting Network Issues

### 8.1 Common Issues and Solutions

| Symptom | Likely Cause | Diagnostic Command | Fix |
|---------|-------------|-------------------|-----|
| Container can't reach COREDB | Tailscale down | `tailscale status` | Restart Tailscale |
| Container can't resolve service name | Wrong network | `docker network inspect <network>` | Add service to correct network |
| Port conflict | Two services on same port | `ss -tlnp \| grep <port>` | Change port or use different host bind |
| Public can't reach service | Traefik config issue | `curl -v https://<host>/health` | Check Traefik labels and dynamic config |
| Container can't reach internet | On internal network | `docker exec <container> curl -v https://google.com` | Move to non-internal network or use proxy |
| Slow inter-container comms | Network congestion | `docker exec <container> ping <other>` | Check host CPU/network; consider dedicated network |
| DNS resolution fails | Docker DNS issue | `docker exec <container> nslookup <name>` | Check /etc/resolv.conf; add explicit dns: |

### 8.2 Network Debugging Commands

```bash
# List all Docker networks
docker network ls

# Inspect a specific network (see connected containers, IPs, subnets)
docker network inspect <network-name>

# Check a container's network configuration
docker inspect <container-name> | jq '.[0].NetworkSettings'

# Run a temporary debug container on a network
docker run --rm -it --network <network> alpine sh

# Test connectivity between containers
docker exec <container-a> curl -v http://<container-b>:<port>/health

# Check Tailscale connectivity
tailscale status
tailscale ping <other-node-hostname>

# Monitor network traffic on a Docker bridge
tcpdump -i br-<network-id> -n

# Check iptables NAT rules for Docker
iptables -t nat -L DOCKER -n -v
```

---

## Appendix A — Network Diagram (ASCII)

```
INTERNET
  │
  │ :443
  ▼
┌───────────────────────────────────────────────────────┐
│ EDGE (187.77.148.88)                                  │
│                                                       │
│  ┌─────────┐     ┌─────────────────────┐              │
│  │ Traefik │────▶│ traefik-public       │              │
│  │  :443   │     │  ├─ nginx           │              │
│  └─────────┘     │  ├─ frontend-app    │              │
│                  │  └─ dashboard       │              │
│                  └─────────────────────┘              │
│                                                       │
│  ┌──────────────────────┐                             │
│  │ edge-internal        │                             │
│  │  └─ edge-services    │                             │
│  └──────────────────────┘                             │
└───────────────────────┬───────────────────────────────┘
                        │
             Tailscale  │  100.110.48.189
                        │
        ┌───────────────┼───────────────────┐
        │               │                   │
        ▼               ▼                   ▼
┌───────────────┐ ┌──────────────┐ ┌──────────────┐
│ AIOPS         │ │ COREDB        │ │ (future node)│
│ 5.78.140.118  │ │ 5.78.210.123 │ │              │
│ 100.121.230.28│ │ 100.118.166.117│ │              │
│               │ │               │ │              │
│ traefik-public│ │ database      │ │              │
│ aiops-internal│ │ monitoring    │ │              │
│ monitoring    │ │               │ │              │
│ per-svc intern│ │               │ │              │
└───────────────┘ └──────────────┘ └──────────────┘
```

## Appendix B — Quick Reference: Adding a New Service

1. **Is it internet-facing?** Add to `traefik-public`.
2. **Does it talk to other services?** Add to `backend` or `aiops-internal`.
3. **Does it access the database?** Add to `database` (or use Tailscale to COREDB).
4. **Does it need internet access?** Ensure the network has `internal: false`.
5. **Does it have a sidecar database?** Create a dedicated `internal: true` network.
6. **Is it monitoring infrastructure?** Add to `monitoring`.

Then verify:
- [ ] Service can resolve and reach its dependencies.
- [ ] Service cannot access networks it shouldn't.
- [ ] Ports are bound to 127.0.0.1 (not 0.0.0.0) unless public.
- [ ] Firewall rules are updated.
- [ ] DNS resolution works for both Docker-internal and external hostnames.
