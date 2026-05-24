# Wheeler AIOps — Operations Quick Reference

## Server Access

| Server            | Role           | Public IP    | Tailscale IP  | SSH Command            |
|-------------------|----------------|--------------|---------------|------------------------|
| Hetzner CPX51     | Primary AIOps  | 5.78.x.x     | 100.121.x.x   | `ssh hetzner`          |
| Hostinger VPS     | Edge / Frontend| x.x.x.x      | 100.98.x.x    | `ssh hostinger`        |

**SSH via Tailscale** (recommended for admin):
```bash
ssh <user>@100.121.x.x    # Hetzner
ssh <user>@100.98.x.x     # Hostinger
```

**SSH Config** (`~/.ssh/config`):
```
Host hetzner
    HostName 5.78.x.x
    User wheeler
    IdentityFile ~/.ssh/id_ed25519

Host hostinger
    HostName x.x.x.x
    User wheeler
    IdentityFile ~/.ssh/id_ed25519
```

---

## Key File Paths

| Path | Purpose |
|------|---------|
| `/opt/wheeler/` | Base installation directory (both servers) |
| `/opt/wheeler/apps/<app>/` | Application compose files |
| `/opt/wheeler/config/envs/` | Environment files (chmod 600) |
| `/opt/wheeler/config/traefik/` | Traefik configuration |
| `/opt/wheeler/data/postgres/` | PostgreSQL persistent data |
| `/opt/wheeler/data/redis/` | Redis persistent data |
| `/opt/wheeler/logs/` | Application and system logs |
| `/opt/wheeler/backups/` | Backup staging area |
| `/opt/wheeler/releases/` | Timestamped release directories |
| `/opt/wheeler/deploy/` | Deployment scripts and symlinks |
| `/opt/wheeler/deploy/current` | Symlink to active release |
| `/opt/wheeler/deploy/previous` | Symlink to previous release |
| `/opt/wheeler/deploy/history.log` | Deployment history log |
| `/opt/wheeler/scripts/` | Operational scripts |
| `/etc/systemd/system/` | Systemd service files |

---

## Common Commands

### Service Management

```bash
# View all services status
./service-manager.sh status

# View a specific service
./service-manager.sh status prediction-radar

# Start / Stop / Restart
./service-manager.sh start prediction-radar
./service-manager.sh stop prediction-radar
./service-manager.sh restart prediction-radar

# View logs
./service-manager.sh logs prediction-radar           # Last 50 lines
./service-manager.sh logs prediction-radar --tail 200
docker logs prediction-radar-api --tail 100 -f       # Direct container logs

# Health check
./service-manager.sh health prediction-radar
```

### Deployment

```bash
# Deploy a single app
./deploy-release.sh prediction-radar main

# Deploy with rollback on failure (automatic)
./deploy-release.sh prediction-radar main            # Health check gates this

# Rollback to previous version
./deploy-release.sh prediction-radar main --rollback
# OR
./deploy-rollback.sh prediction-radar

# Dry run (preview without changes)
./deploy-release.sh prediction-radar main --dry-run

# Full-stack deploy (dependency-ordered)
./deploy-all.sh
./deploy-all.sh --dry-run
./deploy-all.sh --only prediction-radar
./deploy-all.sh --server hostinger

# Environment variables
./env-template.sh prediction-radar --init            # Create new .env
./env-template.sh prediction-radar --validate        # Check required vars
./env-template.sh --list                             # List all env files
```

### System Administration

```bash
# Container management
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker stats                                         # Resource usage
docker compose --project-name prediction-radar ps

# Logs
journalctl -t wheeler-watchdog -n 50                 # Watchdog logs
journalctl -t wheeler-health -n 20                   # Health check logs
tail -f /opt/wheeler/logs/*.log                      # App logs

# Docker networks
docker network ls --filter label=wheeler.io/network=true
docker network inspect traefik-public

# Disk usage
df -h /opt
du -sh /opt/wheeler/releases/*                       # Release sizes
du -sh /opt/wheeler/backups/*                        # Backup sizes
```

### Development

```bash
# Tmux development session
./tmux-dev-workflow.sh                               # Create or attach
./tmux-dev-workflow.sh --attach                      # Attach to session
./tmux-dev-workflow.sh --kill                        # Kill session

# Inside tmux (prefix: Ctrl+a):
#   Ctrl+a 1-6     Jump to window
#   Ctrl+a d        Detach (session keeps running)
#   Ctrl+a |        Split vertical
#   Ctrl+a -        Split horizontal

# Git pre-push hook (install in your repo)
ln -sf ../../shared/git-hooks/pre-push.sh .git/hooks/pre-push
```

---

## Emergency Procedures

### Container keeps crashing

```bash
# 1. Check what's happening
docker logs <container-name> --tail 50

# 2. Check service status
./service-manager.sh status <service>

# 3. Force restart
./service-manager.sh restart <service>

# 4. If still failing, rollback
./deploy-rollback.sh <service>

# 5. Last resort: check the watchdog
journalctl -t wheeler-watchdog -n 20
```

### Server unreachable

```bash
# 1. Check via Tailscale
ping 100.121.x.x                # Hetzner tailscale
ping 100.98.x.x                 # Hostinger tailscale

# 2. Check via public IP
ping <public-ip>

# 3. Check Hetzner Cloud Console / Hostinger panel for power status
# 4. If Hetzner is down, Hostinger Traefik will return 502s
# 5. Check uptime.wheeler.ai for monitoring data
```

### Database issues

```bash
# PostgreSQL
pg_isready -h localhost -p 5432
docker exec -it <postgres-container> psql -U postgres -c "SELECT 1;"

# Redis
redis-cli -h localhost ping
docker exec -it <redis-container> redis-cli ping

# Restore from backup
ls /opt/wheeler/backups/databases/
# Use pg_restore for custom format dumps
```

### Disk space critical

```bash
# 1. Check usage
df -h
du -sh /opt/wheeler/* | sort -rh | head -10

# 2. Clean old releases
#    (systemd timer does this weekly, but manual:)
rm -rf /opt/wheeler/releases/old-release*

# 3. Clean Docker
docker system prune -f --volumes                     # WARNING: removes volumes!
docker image prune -a -f                             # Remove unused images
docker builder prune -f                              # Build cache

# 4. Check logs
ls -lh /opt/wheeler/logs/
ls -lh /var/lib/docker/containers/*/*-json.log       # Docker logs
```

### Rollback needed

```bash
# Automatic (deploy-release handles this on health check failure)

# Manual rollback to previous release:
./deploy-rollback.sh <service>

# Manual rollback to specific release:
./deploy-rollback.sh <service> --to 20250115-143022

# Emergency manual rollback (bypass health checks):
# 1. Stop current
docker compose --project-name <app> down
# 2. Switch symlink
ln -sfn /opt/wheeler/releases/<previous-release> /opt/wheeler/deploy/<app>/current
# 3. Start previous
cd /opt/wheeler/releases/<previous-release>
docker compose --project-name <app> up -d
```

---

## Backup Locations

| What | Where | When |
|------|-------|------|
| PostgreSQL databases | `/opt/wheeler/backups/databases/` | Daily at 03:00 UTC |
| Docker volumes | `/opt/wheeler/backups/volumes/` | Daily at 03:00 UTC |
| Configuration | `/opt/wheeler/backups/configs/` | Daily at 03:00 UTC |
| Off-site archive | rsync to archive server | After local backup |

**Retention:** 7 days on-server, 30 days off-site.

---

## Monitoring URLs

| Service | URL | Notes |
|---------|-----|-------|
| Grafana | `https://grafana.wheeler.ai` | Dashboards |
| Uptime Kuma | `https://uptime.wheeler.ai` | Status page |
| Healthchecks | `https://healthchecks.wheeler.ai` | Cron monitoring |
| Netdata | `http://<tailscale-ip>:19999` | Tailscale only |
| Prometheus | `http://<tailscale-ip>:9090` | Tailscale only |
| Portainer | `https://<tailscale-ip>:9443` | Tailscale only |

---

## Architecture Quick Reference

```
                     Cloudflare (DNS + WAF)
                           |
                    Hostinger Traefik (TLS)
                    /        |         \
            FRGops        n8n        MinIO
            Chatwoot    LiteLLM    Docuseal
                           |
                    Tailscale Mesh
                           |
                     Hetzner Traefik
                    /        |       \
          PredictionR   RavynAI    Trading
          Postgres      Redis      NATS/RabbitMQ
          Analytics     Agents     Monitoring
```

**Security Zones:**
- Zone 0: Public (Cloudflare -> Traefik, ports 80/443)
- Zone 1: Semi-public (Traefik-routed apps with auth)
- Zone 2: Tailscale-only (admin, dashboards, SSH)
- Zone 3: Internal (Docker networks, no host ports)
