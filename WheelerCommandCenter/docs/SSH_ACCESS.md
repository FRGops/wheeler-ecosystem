# Wheeler SSH Access

## SSH Aliases

The Wheeler Command Center uses SSH aliases for fast server access:

```bash
ssh hostinger    # Public production server
ssh hetzner      # AIops control plane
ssh coredb       # Private database server
```

## Required SSH Config

Add to `~/.ssh/config`:

```
# Wheeler Ecosystem Servers
Host hostinger
  HostName TODO_HOSTINGER_PUBLIC_IP
  User root
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host hetzner
  HostName TODO_HETZNER_PUBLIC_IP
  User root
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host coredb
  HostName TODO_COREDB_PUBLIC_IP
  User root
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

**Replace `TODO_*` with actual IPs** (discover via `tailscale status` or `curl -s https://api.ipify.org` on each server).

**Replace `id_ed25519`** with your actual SSH key filename.

## Testing Connectivity

```bash
# Test SSH alias resolves
ssh -G hostinger | grep hostname
ssh -G hetzner | grep hostname
ssh -G coredb | grep hostname

# Test connection
ssh -o ConnectTimeout=5 hostinger "hostname"
ssh -o ConnectTimeout=5 hetzner "hostname"
ssh -o ConnectTimeout=5 coredb "hostname"

# Or use wheeler
wheeler ssh hostinger
```

## Using Tailscale IPs

For more reliable connectivity, use Tailscale IPs in SSH config:

```
Host hostinger
  HostName 100.X.X.X   # Tailscale IP from 'tailscale status'
```

## Troubleshooting

- **Permission denied:** Check IdentityFile path and key permissions (`chmod 600 ~/.ssh/id_*`)
- **Connection timeout:** Verify IP is correct and server is online
- **Host key changed:** Run `ssh-keygen -R <ip>` to clear old key
- **No route to host:** Check Tailscale status (`tailscale status`)
