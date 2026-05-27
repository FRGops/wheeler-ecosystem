# Gap Fix: SSL Certificates + Changedetection Restarts

**Date:** 2026-05-27  
**Audit Run:** 22  
**Status:** Investigation Complete

---

## Gap 1: Missing SSL Certificates for 4 Subdomains

### Environment
- **Server:** Hostinger (`ssh hostinger`)
- **Certbot:** 5.6.0 (installed at `/usr/local/bin/certbot`)
- **Existing certs:** 16 valid Let's Encrypt certificates already provisioned
- **DNS provider:** Cloudflare (`elle.ns.cloudflare.com` / `devin.ns.cloudflare.com` for frgops.io)

### Domain-by-Domain Analysis

#### 1. attorneys.frgops.io
| Check | Result |
|-------|--------|
| DNS A record resolves? | **NO** -- empty response from dig |
| nginx config exists? | YES -- `/etc/nginx/sites-enabled/attorneys-frgops-io` |
| Config purpose | Frontend proxy_pass -> localhost:3301, API proxy_pass -> localhost:8004, Socket.IO -> localhost:8004 |
| SSL setup instructions | Included as comments in config file |
| Can certbot run now? | **NO** -- domain must resolve to this server first |

Config file already contains the exact certbot command to use once DNS is configured:
```
certbot certonly --webroot -w /var/www/html -d attorneys.frgops.io
```
After certbot succeeds, the SSL server block (already templated, currently commented out) must be uncommented and the HTTP block commented out.

#### 2. claimant.frgops.io
| Check | Result |
|-------|--------|
| DNS A record resolves? | **NO** -- empty response from dig |
| nginx config exists? | YES -- `/etc/nginx/sites-enabled/claimant-frgops-io` |
| Config purpose | API proxy_pass -> 100.121.230.28:8103, Frontend proxy_pass -> localhost:3005 |
| SSL setup instructions | None in config |
| Can certbot run now? | **NO** -- domain must resolve to this server first |

#### 3. deals.ravyncapital.io
| Check | Result |
|-------|--------|
| DNS A record resolves? | **NO** -- empty response from dig |
| Parent domain `ravyncapital.io` NS records? | **NONE** -- `dig NS ravyncapital.io @8.8.8.8` returns empty |
| Parent domain WHOIS? | **"Domain not found"** -- domain does not appear to be registered or is at an unresponsive registrar |
| nginx config exists? | YES -- `/etc/nginx/sites-enabled/deals-ravyncapital-io` |
| Config purpose | API proxy_pass -> localhost:8012, Frontend proxy_pass -> localhost:3001 |
| Can certbot run now? | **NO** -- the parent domain ravyncapital.io has no DNS infrastructure. The domain must first be registered/configured with DNS nameservers, then an A record added pointing to Hostinger. |

**Critical finding:** `ravyncapital.io` has no published nameservers and returns "Domain not found" from WHOIS. This is not a subdomain configuration issue -- the entire domain lacks DNS. SSL cannot be provisioned until `ravyncapital.io` DNS is set up at the domain registrar level, nameservers pointed (Cloudflare or other), and an A record for `deals.ravyncapital.io` added.

#### 4. ops.frgops.io
| Check | Result |
|-------|--------|
| DNS A record resolves? | **NO** -- empty response from dig |
| nginx config exists? | YES -- `/etc/nginx/sites-enabled/ops-frgops-io` |
| Config purpose | proxy_pass -> localhost:8102 |
| SSL setup instructions | None in config |
| Can certbot run now? | **NO** -- domain must resolve to this server first |

### Blocking Root Cause (All 4 Domains)

The DNS for these 4 domains simply does not point to the Hostinger server.

- `frgops.io` is on Cloudflare DNS (`elle.ns.cloudflare.com` / `devin.ns.cloudflare.com`) -- A records for `attorneys`, `claimant`, and `ops` must be created in the Cloudflare DNS zone pointing to the Hostinger server IP before certbot can issue certs.
- `ravyncapital.io` has no DNS infrastructure at all -- must be resolved at the registrar level first.

### Fix Commands (Ready to Run After DNS is Configured)

```bash
# Step 1: Set up DNS A records in Cloudflare (frgops.io zone) pointing to Hostinger IP
# For: attorneys.frgops.io, claimant.frgops.io, ops.frgops.io

# Step 2: Obtain SSL certificates with certbot
ssh hostinger "certbot certonly --webroot -w /var/www/html -d attorneys.frgops.io"
ssh hostinger "certbot certonly --webroot -w /var/www/html -d claimant.frgops.io"
ssh hostinger "certbot certonly --webroot -w /var/www/html -d ops.frgops.io"

# Step 3: For each domain, uncomment the SSL server block and comment out the HTTP block
#   in the corresponding nginx config file, then reload:
ssh hostinger "nginx -t && systemctl reload nginx"

# For deals.ravyncapital.io - requires resolving ravyncapital.io DNS at registrar first
```

---

## Gap 2: Changedetection 19 Restarts

### Environment
- **Server:** Hetzner (local)
- **Container name:** `aiops-changedetection` (NOT `changedetection`)
- **Image:** `ghcr.io/dgtlmoon/changedetection.io:0.55.3`

### Investigation Results

| Metric | Value |
|--------|-------|
| Container exists? | **YES** -- named `aiops-changedetection` |
| Current status | **Up 2 days (healthy)** |
| RestartCount | **19** (confirmed via `docker inspect`) |
| OOMKilled | **NO** |
| Created | 2026-05-24T05:56:44 UTC |
| Current uptime | Since 2026-05-24T06:08:07 UTC (~3 days) |
| Memory usage | 103.4 MiB / 512 MiB limit (20.2%) |
| CPU usage | 0.26% |
| Restart policy | `unless-stopped` |
| Errors in logs | **NONE** -- logs show consistent `200` responses every ~30s |
| Port mapping | 127.0.0.1:5000 -> 5000/tcp |

### Analysis

The 19 restarts are a **historical artifact**, not an active issue:

1. Container was created on 2026-05-24 at 05:56 UTC
2. It experienced 19 restart attempts between creation and 06:07 UTC
3. Since 06:08 UTC on 2026-05-24 (approximately 11 minutes after creation), the container has been **running continuously without restarts**
4. Current uptime is approximately 3 days
5. No OOM kills, no errors in logs, resource utilization is well within limits

The restarts were most likely caused by:
- Initial configuration issues during first deployment (e.g., database not ready, config file not found)
- A crash loop that was resolved by the 20th attempt
- The `unless-stopped` restart policy allowed Docker to keep retrying until the container stabilized

### Recommended Action

**No action needed.** The container is healthy and stable. The RestartCount of 19 is a counter that only resets if the container is recreated (docker rm + docker run). This is cosmetic for a container that has been running for 3 days without issue.

If the historical restart count is concerning for monitoring/alerting purposes, the container can be recreated cleanly:
```bash
docker rm -f aiops-changedetection
# Then re-run with original docker run command (would need the original docker-compose or run command)
# Note: Only do this during maintenance window as it will reset the counter
```

---

## Summary

| Gap | Status | Action Required |
|-----|--------|----------------|
| SSL certs for 4 domains | **BLOCKED** on DNS | Configure DNS A records in Cloudflare (frgops.io) and register/configure DNS for ravyncapital.io |
| Changedetection 19 restarts | **NOT AN ISSUE** -- historical artifact, container stable for 3 days | No action needed |

### Services Not Modified During This Investigation
- No nginx configs were changed
- No certbot commands were run
- No Docker containers were restarted or modified
- DNS was not altered
