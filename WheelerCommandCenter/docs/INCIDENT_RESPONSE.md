# Wheeler Incident Response

## 🚨 First Response

```bash
wheeler panic
```

This instantly shows:
- Server reachability
- Domain health
- Docker container status
- Disk/memory warnings
- Backup status
- Emergency SSH commands

## Triage Flow

### 1. Isolate — What's Broken?

```bash
wheeler health          # Full ecosystem health
wheeler domains         # Public sites up?
wheeler docker all      # Containers healthy?
wheeler smoke all       # Apps responding?
```

### 2. Diagnose — Why?

```bash
wheeler logs <service>           # Last 100 lines
wheeler logs <service> --follow  # Live tail
ssh <server> "docker ps --filter health=unhealthy"
ssh <server> "docker stats --no-stream"
ssh <server> "df -h"
ssh <server> "free -m"
```

### 3. Fix — Common Patterns

**Container restarting:**
```bash
ssh <server> "docker ps --filter status=restarting"
ssh <server> "docker logs <container> --tail 50"
ssh <server> "docker restart <container>"
```

**Site down:**
```bash
wheeler domains                       # Check DNS + HTTP
ssh hostinger "docker compose ps"     # Check containers
ssh hostinger "docker compose logs web --tail 100"
```

**Disk full:**
```bash
ssh <server> "df -h"
ssh <server> "docker system prune -a --volumes"  # Careful!
```

### 4. Verify — Fixed?

```bash
wheeler smoke all
wheeler health
wheeler scorecard
```

### 5. Document

Save incident report:
```bash
echo "Incident: $(date)" > ~/WheelerCommandCenter/reports/incident-$(date +%Y%m%d-%H%M).md
```

## Emergency Contacts (fill in)

- **Hostinger:** TODO
- **Hetzner:** TODO
- **CoreDB:** TODO

## Recovery Commands

```bash
# Emergency SSH (if wheeler is down)
ssh hostinger  # or hetzner, coredb

# Restart Docker daemon
ssh <server> "systemctl restart docker"

# Restart PM2
ssh <server> "pm2 resurrect"

# Check system logs
ssh <server> "journalctl -xe --no-pager -n 50"
```
