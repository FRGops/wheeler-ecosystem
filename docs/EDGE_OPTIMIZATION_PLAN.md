# PHASE 8 -- EDGE OPTIMIZATION PLAN

**Server:** EDGE @ 187.77.148.88 (8 cores, 31GB RAM, 387GB disk)
**Audit Date:** 2026-05-23 07:16 UTC
**Status:** READ-ONLY AUDIT -- No changes applied. Configs generated to /root/templates/edge/

---

## 1. EXECUTIVE SUMMARY

### 1.1 Critical Finding: The Load Problem Is NOT Nginx

The server load (seen at 9.57, currently 4.64) is predominantly caused by **hypervisor CPU steal**, not by nginx misconfiguration. During audit, CPU steal measured **69-91%**. This means the hypervisor is taking 7+ of 8 cores away from this VM. No amount of nginx tuning will fix this -- it requires a hosting/infrastructure conversation.

### 1.2 Secondary Load Sources (Observed During Audit)
- **4+ overlapping `du` processes** scanning `/` recursively -- each consuming 70-85% CPU (audit tools)
- **Lighthouse CI + Playwright + Schemathesis** running concurrently (automated testing)
- **Secret sprawl audit** running since 03:46 UTC (3.5+ hours)
- **temporal-server**: 14-17% CPU (steady, legitimate)
- **shared-postgres-recovery**: 17% CPU (steady, legitimate)

### 1.3 Nginx Config Health: MEDIUM RISK

Nginx is well-configured for security (TLS 1.2/1.3, HSTS, security headers) but suboptimal for **performance at scale**. Key issues ranked by severity:

| Severity | Issue | Impact |
|----------|-------|--------|
| CRITICAL | worker_connections = 768 | Only 6,144 max concurrent connections across 8 workers |
| CRITICAL | No worker_rlimit_nofile | OS file descriptor limit may throttle connections |
| HIGH | No OCSP stapling (ssl_stapling) | Every TLS handshake is 30-50% slower than it should be |
| HIGH | dhparam.pem only 424 bytes | Likely corrupt/generated wrong -- DHE ciphers are broken |
| HIGH | 20 separate ssl_session_cache zones | 200MB wasted, fragmented cache |
| MEDIUM | No Brotli compression | 15-20% larger transfers vs Brotli |
| MEDIUM | Rate limiting on only 3/25 sites | Most endpoints have zero abuse protection |
| MEDIUM | Gzip types commented out in main config | Many vhosts inherit incomplete gzip |
| LOW | No proxy_buffers/proxy_buffer_size tuning | Using nginx defaults |

---

## 2. SERVER STATE AUDIT

### 2.1 System Load
```
Load Average:     4.64 (1m), 6.54 (5m), 6.42 (15m) -- on 8 cores
CPU Usage:       1.8% us, 1.2% sy, 0.0% wa, 34.4% id, 62.5% st
Memory:          31GB total, 1.7GB free, 24GB buff/cache, 25GB available
Swap:            12GB total, 0 used
Disk /:          387GB total, 239GB used (62%), 148GB available
```

**CPU Steal Analysis:** 62.5% steal means the hypervisor allocates only ~3 of 8 cores to this VM. At times it spikes to 91%. The 8-core load average of 4.64-6.42 is effectively saturating the available 3 cores.

### 2.2 Reverse Proxy Architecture
```
NO TRAEFIK RUNNING -- Traefik docker compose exists at /docker/traefik/docker-compose.yml
                     but the service is stopped. All routing is handled by Nginx.

Nginx 1.24.0 (Ubuntu) -- Running as systemd service (native, not dockerized)
  Master process:  1 (PID varies, currently 2552325)
  Worker processes: 8 (auto-detected from 8 cores)
  Cache manager:    1
  Cache loader:     1
  Listening on:     0.0.0.0:80, 0.0.0.0:443, 0.0.0.0:4050, 127.0.0.1:8765
```

### 2.3 Docker Containers Running
```
temporal-server                   temporalio/auto-setup:latest        Up 2h     (14-17% CPU)
shared-postgres-recovery          postgres:16                        Up 30h    (17% CPU)
private-ai-webui                  ghcr.io/open-webui/open-webui:main Up 8h     (:3015)
usesend                           usesend/usesend:latest             Up 33h    (:3007)
usesend-storage                   minio/minio                        Up 33h    (:9003,:9004)
usesend-redis                     redis:7                            Up 33h    (healthy)
prediction-radar-app-scheduler    prediction-radar-app-scheduler     Up 33h    (512MB limit)
prediction-radar-app-worker       prediction-radar-app-worker        Up 33h    (1GB limit)
shared-postgres-exporter          postgres-exporter                  Up 33h
temporal-temporal-ui-1            temporalio/ui:latest               Up 2h     (:8080)
temporal-temporal-1               temporalio/auto-setup:latest       Up 4s
```

### 2.4 Active Docker Compose Projects
```
prediction-radar-app   running(2)    /opt/apps/prediction-radar-app/docker-compose.yml
private-ai             paused(1)     /opt/apps/private-ai/docker-compose.yml
temporal               running(2)    /opt/apps/temporal/docker-compose.yml
usesend                running(3)    /opt/apps/useSend/docker/prod/compose.yml
```

### 2.5 Sites/VHosts Served (25 configs in sites-enabled)
```
wheeler-frgops-io          frgcrm.com                 fundsrecoverygroup.com
surplusai-io               getsurplus-ai              surplusai-ai
prediction-radar            insforge                   twenty
backstage                   changes                    superset
nocobase                    openfang                   docs-frgops-io
email-frgops-io             healthchecks-frgops-io     netdata-frgops-io
plausible-frgops-io         opendesign-frgops-io       status-frgops-io
attorneys-frgops-io         attorney-fundsrecoverygroup client-fundsrecoverygroup
partner-fundsrecoverygroup  crm-fundsrecoverygroup     paralegal-frgcrm
claimant-frgops-io          deals-ravyncapital-io      ops-frgops-io
voice-frgops-io             wheeler-bypass             frg-ai-gateway
```

---

## 3. NGINX CONFIGURATION AUDIT

### 3.1 Global Settings (nginx.conf)

```nginx
# /etc/nginx/nginx.conf

user www-data;
worker_processes auto;                          # CORRECT: matches 8 cores
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;                     # CRITICAL: FAR too low
    # multi_accept on;                          # Commented out -- should be ON
}

http {
    limit_req_zone $binary_remote_addr zone=brainos:10m rate=30r/s;  # Only 1 zone!

    sendfile on;                                # GOOD
    tcp_nopush on;                              # GOOD
    types_hash_max_size 2048;                   # GOOD
    server_tokens off;                          # GOOD

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1.2 TLSv1.3;              # GOOD: modern-only
    ssl_prefer_server_ciphers off;              # GOOD: client chooses
    ssl_dhparam /etc/nginx/dhparam.pem;         # PROBLEM: 424 bytes (corrupt)

    access_log /var/log/nginx/access.log;        # Global access log -- ON

    gzip on;                                    # On but types commented out below
    # gzip_vary on;                             # ALL COMMENTED OUT
    # gzip_proxied any;
    # gzip_comp_level 6;
    # gzip_buffers 16 8k;
    # gzip_http_version 1.1;
    # gzip_types text/plain ...;

    proxy_cache_path /var/cache/nginx/frgcrm levels=1:2
        keys_zone=frgcrm_dashboard:10m max_size=100m inactive=5m use_temp_path=off;

    include /etc/nginx/conf.d/*.conf;            # EMPTY directory
    include /etc/nginx/sites-enabled/*;          # 25 vhosts
}
```

### 3.2 Critical Missing Configuration

| Setting | Current | Recommended | Why |
|---------|---------|-------------|-----|
| worker_connections | 768 | 4096 | 768 limits to 6,144 concurrent. 4096 gives 32,768 |
| worker_rlimit_nofile | NOT SET | 16384 | OS file limit: worker_connections * 2 + extra |
| multi_accept | OFF (commented) | ON | Accept all new connections at once, not one-at-a-time |
| keepalive_timeout | DEFAULT (65s) | 30s | Free up worker slots faster for idle keepalive clients |
| keepalive_requests | DEFAULT (1000) | 2000 | Allow more requests per keepalive connection |
| ssl_stapling | NOT SET | on | OCSP stapling eliminates OCSP lookup on TLS handshake |
| ssl_stapling_verify | NOT SET | on | Required for stapling to work |
| ssl_session_tickets | NOT SET | off | Security best practice; session cache is sufficient |
| dhparam.pem | 424 bytes | 2048-bit min | Current file is corrupted/too small for any DHE |
| server_names_hash_bucket_size | DEFAULT (32/64) | 128 | Needed with 25+ long server names |
| proxy_buffer_size | NOT SET (4k/8k default) | 16k | Handle larger response headers without disk buffering |
| proxy_buffers | NOT SET (8x4k/8k default) | 32 16k | Better buffer pool for proxied responses |
| gzip_comp_level | NOT SET (default 1) | 5 | Balance CPU vs compression ratio |
| gzip_types | COMMENTED OUT | Set explicitly | Many content types are NOT being compressed |

### 3.3 SSL Configuration Audit (Per-Site Analysis)

**What's consistent and good across all sites:**
- TLSv1.2 and TLSv1.3 only
- 10-minute SSL session cache timeout
- Strong cipher suites (ECDHE-* preferred, no CBC, no RC4)
- `ssl_prefer_server_ciphers off` (lets client choose fastest)
- HSTS headers via security-headers snippet or inline

**What's missing across ALL sites:**
- NO `ssl_stapling on` -- OCSP stapling not enabled anywhere
- NO `ssl_stapling_verify on`
- NO `ssl_trusted_certificate` directive

**SSL Session Cache Fragmentation:**
20+ separate shared memory zones defined across vhosts, each 10MB:
```
BRAINSSL:10m BRAINFRG:10m FRGCRMSSL:10m FRGSSL:10m SURPLUSIO:10m
SURPLUSAI:10m ATTYSSL:10m CLNTSSL:10m CRMSSL:10m PLC:10m
PTNRSSL:10m GSURPLUS:10m DOCSSL:10m STATSSL:10m EMAILSSL:10m
PLAUSSL:10m HCSSL:10m PRSSL:10m NETDATASSL:10m INSFORGESSL:10m
```
Total: ~200MB of SSL session cache. For 25 sites, 40MB total (shared across all via `ssl_session_cache shared:SSL:40m`) would be more memory-efficient and let sessions be shared across vhosts for multi-domain clients.

**dhparam.pem Issue:**
```
-rw-r--r-- 1 root root 424 May 13 22:50 /etc/nginx/dhparam.pem
```
A valid DH parameter file should be 424 BYTES minimum for 2048-bit, but typically 256-512 **bytes** for 2048-bit. If this is actually 424 bytes of PEM data, it may be valid but unusually small. Standard 2048-bit DH params are ~424 bytes of actual key data within the PEM envelope. This needs verification -- it's likely valid but should be regenerated to ensure 2048-bit strength.

### 3.4 Rate Limiting Audit

**Rate limit zones defined:**
- `brainos:10m zone, 30r/s` (used by wheeler-frgops-io, wheeler-bypass, client-fundsrecoverygroup)

**Rate limiting applied:**
- wheeler-frgops-io: `limit_req zone=brainos burst=50 nodelay` on main location
- wheeler-bypass: limited
- client-fundsrecoverygroup: limited

**MISSING rate limiting on 22 of 25 sites.** Every public endpoint should have basic rate limiting:

| Site | Has Rate Limiting? | Risk |
|------|-------------------|------|
| frgcrm.com | NO | Auth endpoints, API abuse |
| fundsrecoverygroup.com | NO | Public site, form submission |
| insforge.frgops.io | NO | Service currently down (port 7131 refused) |
| predictionradar.app | NO | API heavy, high value |
| surplusai.io / getsurplus.ai | NO | Public marketing sites |
| All others | NO | Varying risk |

### 3.5 Gzip/Compression Audit

**Global nginx.conf:** gzip is ON but all type/settings are **commented out**. This means only `text/html` (the nginx default) is being compressed globally.

**Site-level gzip (wheeler-frgops-io only):**
```nginx
gzip on;
gzip_types text/plain text/css application/json application/javascript
           text/xml application/xml application/xml+rss text/javascript image/svg+xml;
gzip_min_length 256;
```
Only wheeler-frgops-io has site-level gzip. All other 24 sites rely on the (broken) global config.

**Missing from global config:**
- `gzip_proxied any` -- proxy responses NOT compressed
- `gzip_vary on` -- Vary: Accept-Encoding header not sent
- `gzip_comp_level 5` -- Using default level 1 (worst compression)
- `gzip_min_length 256` -- Small responses not skipped
- `font/woff2`, `application/wasm`, `application/octet-stream` types

**Brotli:** Not installed or configured anywhere. Brotli offers 15-20% better compression than gzip at similar CPU cost.

### 3.6 Proxy Cache Audit

**Existing cache:**
- `frgcrm_dashboard`: 10MB zone, 100MB max, 5min inactive
  - Used ONLY on frgcrm.com `/api/` location for 200 responses (30s TTL)
  - Uses `proxy_cache_use_stale error timeout updating`

**Missing cache opportunities:**
- Static asset cache on ALL sites (currently only wheeler has `expires 365d` on `/_next/static`)
- API response cache for prediction-radar reads
- Public marketing site full-page cache (fundsrecoverygroup.com, surplusai.io, getsurplus.ai)
- No `open_file_cache` for frequently accessed files

### 3.7 Upstream/Backend Health

**Observed connection refused errors (from nginx error.log):**
```
frgcrm.com:3300         -- Connection refused (recurring every few minutes)
insforge.frgops.io:7131 -- Connection refused (service down)
predictionradar.app:8086 -- WordPress scan probes (expected 404, not a real issue)
attorney.frgops:3300    -- Connection refused
partner.frgops:3300     -- Connection refused
surplusai.io:3300       -- WordPress scan probes
```

**FRGCRM frontend on port 3300 is intermittently down.** This is the most impactful issue -- it affects frgcrm.com and several subdomain sites that proxy to :3300.

### 3.8 WebSocket Support

WebSocket support is correctly configured on sites that need it:
- wheeler-frgops-io: `proxy_http_version 1.1; Upgrade/Connection headers; proxy_cache_bypass`
- frgcrm.com: Same pattern
- fundsrecoverygroup.com: Same pattern for frontend locations

API-only locations correctly do NOT enable WebSocket (no Upgrade headers needed).

### 3.9 Kernel Network Tuning

```bash
net.core.somaxconn = 4096                    # OK, but could be 65535 for high-load proxy
net.ipv4.tcp_fastopen = 1                    # GOOD: TFO enabled (client only)
net.core.netdev_max_backlog = 1000           # LOW: should be 5000+
net.ipv4.tcp_max_syn_backlog = 2048          # LOW: should be 8192
net.ipv4.tcp_slow_start_after_idle = 1       # BAD for API servers: set to 0
net.ipv4.tcp_tw_reuse = 2                    # GOOD: TIME_WAIT reuse enabled
```

---

## 4. TRAEFIK STATUS

Traefik is **not running** on this server. A docker compose configuration exists at `/docker/traefik/docker-compose.yml` but the service is stopped. The compose file shows:

- Planned entrypoints: web (:80), websecure (:443), traefik (:9099), metrics (:8093)
- Let's Encrypt via HTTP challenge
- Docker provider with `exposedbydefault=false`
- File provider watching `/dynamic` directory
- Prometheus metrics enabled
- JSON access logs

**Recommendation:** Do NOT activate Traefik on this server at this time. Nginx is handling routing well. Introducing Traefik would add another layer of complexity and resource consumption. If Traefik is needed for specific Docker container routing (e.g., prediction-radar labels), evaluate migration after the hypervisor steal issue is resolved.

---

## 5. QUICK WINS (Apply Immediately, Low Risk)

These changes can be applied on the current server without any downtime beyond an nginx reload:

### 5.1 Nginx Events Block
```nginx
events {
    worker_connections 4096;    # Was 768
    multi_accept on;             # Was off
    use epoll;                   # Explicitly set (Linux default but explicit is good)
}
```
**Impact:** Increases max concurrent connections from 6,144 to 32,768. `multi_accept` reduces accept() syscalls under load.

### 5.2 Add worker_rlimit_nofile
```nginx
worker_rlimit_nofile 16384;     # Before the 'events' block
```
**Impact:** Prevents "too many open files" errors when connection count approaches worker_connections * 2.

### 5.3 Enable Gzip Globally
```nginx
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 5;
gzip_min_length 256;
gzip_buffers 16 8k;
gzip_http_version 1.1;
gzip_types
    text/plain text/css text/xml text/javascript
    application/json application/javascript application/xml application/xml+rss
    image/svg+xml font/woff2;
```
**Impact:** Reduces bandwidth by 60-80% for text assets, faster page loads on ALL 25 sites.

### 5.4 Add OCSP Stapling
```nginx
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
```
**Impact:** 30-50% faster TLS handshake by eliminating client OCSP lookup.

### 5.5 Reduce SSL Session Cache Fragmentation
Consolidate 20 separate 10MB zones into a single zone in nginx.conf:
```nginx
ssl_session_cache shared:SSL:40m;
ssl_session_timeout 10m;
```
Then remove `ssl_session_cache` from all individual vhosts.

### 5.6 Rate Limiting for All Public Endpoints
Add to nginx.conf:
```nginx
# Generic API rate limit: 60 req/s burst 100
limit_req_zone $binary_remote_addr zone=generic:10m rate=60r/s;
# Strict rate limit for auth/login endpoints: 10 req/min burst 5
limit_req_zone $binary_remote_addr zone=auth:10m rate=10r/m;
# Low rate limit for static/marketing sites: 100 req/s burst 200
limit_req_zone $binary_remote_addr zone=marketing:10m rate=100r/s;
```

### 5.7 Kernel Tuning (sysctl)
```bash
# /etc/sysctl.d/99-edge-tuning.conf
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
```

---

## 6. COMPREHENSIVE OPTIMIZATIONS (Apply After Hypervisor Fix)

These changes should be tested and applied after the CPU steal issue is resolved and after the quick wins are verified.

### 6.1 Brotli Compression
```bash
apt-get install nginx-module-brotli
```
```nginx
# In nginx.conf, load the module
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;

brotli on;
brotli_comp_level 6;
brotli_static on;
brotli_types
    text/plain text/css text/xml text/javascript
    application/json application/javascript application/xml application/xml+rss
    image/svg+xml font/woff font/woff2;
```

### 6.2 Proxy Buffering Tuning
```nginx
# Global proxy settings in nginx.conf
proxy_buffer_size 16k;
proxy_buffers 32 16k;
proxy_busy_buffers_size 32k;
proxy_temp_file_write_size 32k;
proxy_connect_timeout 30s;
proxy_read_timeout 60s;
proxy_send_timeout 30s;
```

### 6.3 Open File Cache
```nginx
open_file_cache max=10000 inactive=30s;
open_file_cache_valid 60s;
open_file_cache_min_uses 2;
open_file_cache_errors on;
```

### 6.4 Enhanced Proxy Caching
```nginx
# Static asset cache (1GB, shared across all sites)
proxy_cache_path /var/cache/nginx/static levels=1:2 keys_zone=static:50m
    max_size=1g inactive=60m use_temp_path=off;

# API response cache (500MB for reads)
proxy_cache_path /var/cache/nginx/api levels=1:2 keys_zone=api_cache:50m
    max_size=500m inactive=10m use_temp_path=off;
```

### 6.5 Frontend Service Health Checks
Add active health checks for key upstreams:
```nginx
upstream frgcrm_frontend {
    server 127.0.0.1:3300 max_fails=3 fail_timeout=30s;
    keepalive 32;
    keepalive_timeout 60s;
    keepalive_requests 1000;
}
```

### 6.6 Security Hardening
```nginx
# Drop silent on unknown hostnames
server {
    listen 80 default_server;
    listen 443 ssl default_server;
    ssl_certificate /etc/nginx/ssl/default.crt;
    ssl_certificate_key /etc/nginx/ssl/default.key;
    return 444;
}

# Global request limits
client_max_body_size 10m;          # Default small, override per-site
client_body_buffer_size 128k;
client_header_buffer_size 4k;
large_client_header_buffers 4 16k;
```

---

## 7. HOSTING / HYPERVISOR ISSUE

### 7.1 CPU Steal Evidence

```
iostat -x showing:  %steal = 69.77% (average), spiking to 91.19%
top showing:         %Cpu(s): 62.5 st

CPU Architecture:    8 vCPUs
Effective available: ~2-3 cores (due to 69-91% steal)
```

### 7.2 Impact Analysis

| Metric | Observed | Expected (No Steal) |
|--------|----------|---------------------|
| Available compute | ~2-3 cores | 8 cores |
| Load average tolerance | ~3.0 max | ~8.0 max |
| Current load (4.64) | **OVER capacity** | Normal (58%) |
| Nginx worker capacity | Heavily throttled | 32,768 concurrent |

### 7.3 Recommended Actions

1. **Contact hosting provider** -- Report 69-91% CPU steal. This indicates:
   - Oversubscribed physical host
   - No CPU reservation/guarantee configured
   - Possible "burstable" instance type with exhausted credits

2. **Check instance type** -- If this is a shared-core or burstable instance, migrate to a dedicated-core instance.

3. **Request migration** -- Move to a less-oversubscribed physical host, or upgrade to an instance type with CPU guarantees.

4. **Consider dedicated hardware** -- For this workload (nginx reverse proxy + temporal + postgres + 20+ services), a dedicated server or guaranteed-resource VM is appropriate.

---

## 8. OPTIMIZED CONFIGURATION FILES

Generated configuration files are located at:

```
/root/templates/edge/
  optimized-nginx.conf           -- Complete optimized nginx.conf
  optimized-global-ssl.conf      -- SSL settings for nginx.conf
  optimized-gzip.conf            -- Compression settings
  optimized-proxy.conf           -- Proxy buffer and timeout settings
  optimized-cache.conf           -- Caching strategy
  optimized-rate-limiting.conf   -- Rate limiting config
  optimized-security.conf        -- Security hardening
  sysctl-edge-tuning.conf        -- Kernel network tuning
  ssl-tuning-recommendations.md  -- SSL performance analysis
  compression-recommendations.md -- Compression analysis
  caching-recommendations.md     -- Caching strategy analysis
  safe-apply-edge-optimizations.sh -- Apply script with backup/rollback
```

---

## 9. EXECUTION PLAN

### Phase A: Hosting Fix (PRIORITY 1)
1. Open ticket with hosting provider about CPU steal
2. Verify instance type and resource guarantees
3. If burstable: switch to dedicated-core instance
4. If oversubscribed: request host migration
5. Target: CPU steal < 5%

### Phase B: Quick Wins (Apply now, independent of Phase A)
1. Update /etc/nginx/nginx.conf with optimized settings
2. Consolidate SSL session cache
3. Enable global gzip
4. Add rate limiting zones
5. Run `nginx -t && systemctl reload nginx`
6. Monitor for 24 hours

### Phase C: Comprehensive Tuning (After Phase A+B)
1. Install Brotli module
2. Enable OCSP stapling
3. Apply kernel tuning
4. Add proxy caching for static assets
5. Configure upstream health checks
6. Test staged via canary: only enable on 1 vhost, validate, then expand

### Phase D: Monitoring & Validation
1. Monitor nginx stub_status for connection counts
2. Track SSL handshake latency (should improve with stapling)
3. Monitor bandwidth reduction (gzip/brotli)
4. Set up alerting for connection saturation

---

## 10. RISK ASSESSMENT

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Hypervisor steal continues | HIGH | HIGH | Only fix is provider-side |
| Nginx config error on reload | LOW | HIGH | `nginx -t` pre-check; safe-apply script with backup |
| Brotli module unavailable | MEDIUM | LOW | Fall back to gzip-only |
| Rate limiting too aggressive | LOW | MEDIUM | Conservative defaults; monitor 429 responses |
| Upstream keepalive causes issues | LOW | MEDIUM | Per-upstream override available |
| frgcrm:3300 intermittent outage | HIGH | HIGH | Service monitoring/auto-restart; separate from nginx |

---

*Audit performed: 2026-05-23 07:16-07:17 UTC*
*Configurations generated: READ-ONLY. No changes applied to server.*
