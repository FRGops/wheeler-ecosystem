---
name: private-network-check
description: "Network security audit: Tailscale mesh verification, UFW rules check, public port scan, Docker network isolation, private IP routing verification."
trigger: private network, network check, network audit, check network, firewall audit, tailscale check, network security
---

# Skill: Private Network Check

Verify the Wheeler private network (Tailscale mesh + private IPs) is properly isolated. No internal services exposed to the public internet.

## Audit Steps

### Step 1: Tailscale Mesh Health
```bash
tailscale status
```
Requirement: All expected peers connected. No unauthorized peers.

### Step 2: Firewall Rules
```bash
ufw status verbose
```
Requirement: UFW active. Default deny incoming. Only approved ports allowed for public.

### Step 3: Public Port Exposure
```bash
# What's visible from the internet?
ss -tulpn | grep -E '0\.0\.0\.0|:::'
```
Requirement: Only explicitly approved services on public. All DB, Redis, internal APIs on 127.0.0.1.

### Step 4: Docker Network Isolation
```bash
docker network ls
docker network inspect bridge
```
Requirement: No containers with sensitive data on host network. Use bridge/overlay networks.

### Step 5: Private IP Routing
```bash
ip route show | grep -E '10\.|172\.|100\.'
```
Requirement: Private routes exist for Tailscale (100.x) and private network (10.x).

### Step 6: SSH Hardening
```bash
grep -E '^PermitRootLogin|^PasswordAuthentication|^Port' /etc/ssh/sshd_config
grep -E '^PermitRootLogin|^PasswordAuthentication' /etc/ssh/sshd_config.d/*.conf 2>/dev/null
```
Requirement: Key-only auth. No root password login. Non-standard port recommended.

## Approved Public Ports Template

| Port | Service | Justification | Review Date |
|------|---------|---------------|-------------|
| 80/443 | Traefik/nginx | Web ingress | — |
| 22 | SSH | Admin access | — |

Everything else on 127.0.0.1 or Tailscale only.

## Output Format

```
PRIVATE NETWORK CHECK: <hostname> (<public-ip>)
──────────────────────────────────────
TAILSCALE: [CONNECTED] <N> peers active
FIREWALL:  [ACTIVE] default deny incoming
PUBLIC:    <N> ports exposed
  <port> — <service> [APPROVED / NEEDS REVIEW]
DOCKER:    <N> networks, <N> on host [OK/WARN]
SSH:       [HARDENED / NEEDS HARDENING]

──────────────────────────────────────
OVERALL: [SECURE / EXPOSED — <N> issues / CRITICAL]
```
