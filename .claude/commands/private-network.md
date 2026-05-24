# /private-network — Private Network Verification

Verify that the Wheeler private network (Tailscale mesh + private IPs) is properly isolated and no internal services are exposed to the public internet.

## Execution (ALL in parallel)

```bash
# 1. Tailscale mesh status
tailscale status 2>/dev/null

# 2. UFW firewall rules
ufw status verbose 2>/dev/null

# 3. Public port exposure check (what's visible from outside?)
ss -tulpn 2>/dev/null | grep -E '0\.0\.0\.0|:::' | grep -v '127.0.0.1'

# 4. Verify critical services are NOT on public IP
# Check each service port against the public interface
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "5.78.140.118")
echo "Public IP: $PUBLIC_IP"
ss -tulpn 2>/dev/null | grep -E '0\.0\.0\.0|:::' | while read line; do
  port=$(echo "$line" | awk '{print $5}' | grep -oP ':\d+' | head -1 | tr -d ':')
  if [ -n "$port" ]; then
    echo "[CHECK] Port $port is bound to 0.0.0.0 — verify if this is intentional"
  fi
done

# 4. Docker network isolation
docker network ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}' 2>/dev/null
docker network inspect bridge 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
containers = data[0].get('Containers', {})
for cid, c in containers.items():
    print(f'  {c[\"Name\"]:40s} {c[\"IPv4Address\"]}')
" 2>/dev/null

# 5. Private IP routing
ip route show 2>/dev/null | grep -E '10\.|172\.|192\.168\.'

# 6. SSH hardening check
grep -E '^PermitRootLogin|^PasswordAuthentication|^Port' /etc/ssh/sshd_config 2>/dev/null
grep -E '^PermitRootLogin|^PasswordAuthentication' /etc/ssh/sshd_config.d/*.conf 2>/dev/null

# 7. iptables quick check (supplementary to UFW)
iptables -L INPUT -n --line-numbers 2>/dev/null | head -30
```

## Security Minimums

| Service | Must Be | Current |
|---------|---------|---------|
| PostgreSQL | 127.0.0.1 only | <check> |
| Redis | 127.0.0.1 or private IP | <check> |
| Internal APIs | 127.0.0.1 or Tailscale | <check> |
| SSH | Key-only auth | <check> |
| Monitoring | Tailscale or authenticated | <check> |

## Output Format

```
╔══════════════════════════════════════════════╗
║   Private Network Audit — <timestamp>        ║
║   Node: <hostname> (<public-ip>)             ║
╚══════════════════════════════════════════════╝

TAILSCALE: [CONNECTED / DISCONNECTED]
  Peers: <N> active
  <list peers with status>

FIREWALL: [ACTIVE / INACTIVE]
  Public ports: <N> open
  <list any public ports with service name>

DOCKER ISOLATION: [OK / NEEDS REVIEW]
  Networks: <N> bridge, <N> overlay

SSH: [HARDENED / NEEDS HARDENING]
  Root login: <status>
  Password auth: <status>

──────────────────────────────────────────────
OVERALL: [SECURE / EXPOSED — <N> issues / CRITICAL]
```
