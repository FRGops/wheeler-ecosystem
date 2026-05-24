# Caching Recommendations for EDGE Server

## Current State

| Cache Type | Status | Details |
|------------|--------|---------|
| Proxy cache (frgcrm_dashboard) | EXISTS | 10MB zone, 100MB max, 5min inactive, used only by FRGCRM /api/ |
| Static asset cache | LIMITED | Only wheeler-frgops-io has `expires 365d` on `/_next/static` |
| FastCGI cache | NONE | Not applicable (no PHP backends) |
| Open file cache | NONE | Not configured |
| Browser cache headers | INCONSISTENT | Some sites set no-cache, others don't set any |
| CDN cache (Cloudflare) | PARTIAL | Some domains use Cloudflare, others direct |

## Target State

Three-tier caching strategy:
1. **Browser cache** via Cache-Control/Expires headers
2. **Nginx proxy cache** for API reads and static assets
3. **Nginx open file cache** for frequently accessed files

## Cache Zones (add to nginx.conf http block)

```nginx
# Static Asset Cache (1 GB)
# Stores: /_next/static, /static, /assets/ files
# evicted after 60 minutes of inactivity
proxy_cache_path /var/cache/nginx/static
    levels=1:2
    keys_zone=static_cache:50m
    max_size=1g
    inactive=60m
    use_temp_path=off;

# API Response Cache (500 MB)
# Stores: GET /api/dashboard, GET /api/markets, GET /api/leads
# evicted after 10 minutes of inactivity
proxy_cache_path /var/cache/nginx/api
    levels=1:2
    keys_zone=api_cache:50m
    max_size=500m
    inactive=10m
    use_temp_path=off;

# Full-Page Cache for Marketing Sites (500 MB)
# Stores: Complete HTML pages for anonymous users
# evicted after 30 minutes
proxy_cache_path /var/cache/nginx/pages
    levels=1:2
    keys_zone=pages_cache:50m
    max_size=500m
    inactive=30m
    use_temp_path=off;
```

**Total disk usage:** ~2 GB (safe with 148 GB free on /)

## Cache Strategy Per Content Type

### Strategy A: Immutable Static Assets

For: `/_next/static/*`, `/static/js/*.chunk.js`, `/static/css/*.chunk.css`

```nginx
location /_next/static {
    proxy_pass http://localhost:3005;

    # 1 year browser cache (immutable hashed filenames)
    expires 365d;
    add_header Cache-Control "public, immutable";

    # Nginx proxy cache
    proxy_cache static_cache;
    proxy_cache_valid 200 365d;
    proxy_cache_use_stale error timeout updating;
    proxy_cache_key "$uri";

    add_header X-Cache-Status $upstream_cache_status;
}
```

### Strategy B: API Read Responses

For: `GET /api/dashboard`, `GET /api/leads`, `GET /api/markets`

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:8002;

    # Cache GET responses for 30 seconds
    proxy_cache api_cache;
    proxy_cache_valid 200 30s;
    proxy_cache_valid 404 1m;
    proxy_cache_key "$scheme$request_method$uri$args";
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503;

    # Bypass cache for non-GET or nocache param
    proxy_cache_bypass $cookie_nocache $arg_nocache;
    proxy_no_cache $cookie_nocache $arg_nocache;

    add_header X-Cache-Status $upstream_cache_status;

    # Client-side: 5 second stale-while-revalidate
    add_header Cache-Control "public, max-age=5, stale-while-revalidate=30";
}
```

### Strategy C: Full-Page Cache for Anonymous Users

For: Marketing pages (fundsrecoverygroup.com, getsurplus.ai, surplusai.io)

```nginx
# Define cache key that includes device type
map $http_user_agent $device_type {
    default           "desktop";
    ~*Mobile          "mobile";
    ~*Tablet          "tablet";
}

# In server block:
location / {
    proxy_pass http://localhost:3003;

    # 5 minute full-page cache
    proxy_cache pages_cache;
    proxy_cache_valid 200 5m;
    proxy_cache_valid 301 302 1h;
    proxy_cache_valid 404 1m;
    proxy_cache_key "$scheme$request_method$host$uri$device_type";
    proxy_cache_use_stale error timeout updating;

    # Bypass cache for logged-in users or POST requests
    proxy_cache_bypass $http_authorization $cookie_session $arg_preview;
    proxy_no_cache $http_authorization $cookie_session;

    add_header X-Cache-Status $upstream_cache_status;
    add_header Cache-Control "public, max-age=300, stale-while-revalidate=600";
}
```

### Strategy D: Never-Cache (Auth/Personal/Dynamic)

For: Service workers, auth responses, real-time data

```nginx
location = /sw.js {
    add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
    add_header Pragma "no-cache" always;
    add_header Expires "0" always;
    proxy_cache off;
}
```

### Strategy E: Images and Fonts (Long Cache)

For: `*.png`, `*.jpg`, `*.woff2`, `*.svg` (non-hashed)

```nginx
location ~* \.(jpg|jpeg|png|gif|ico|svg|woff|woff2|ttf|eot|otf)$ {
    expires 30d;
    add_header Cache-Control "public, max-age=2592000";
    add_header Vary "Accept-Encoding";
    proxy_cache static_cache;
    proxy_cache_valid 200 30d;
    proxy_cache_use_stale error timeout updating;
}
```

## Open File Cache

Reduces disk I/O for frequently accessed files (error pages, static HTML):

```nginx
# In http block
open_file_cache max=10000 inactive=30s;
open_file_cache_valid 60s;
open_file_cache_min_uses 2;
open_file_cache_errors on;
```

## Cache Hierarchy Summary

```
Request Flow:
  Browser
    |
    v
  [Browser Cache] -- Cache-Control: public, max-age=N
    | (cache miss)
    v
  [Cloudflare CDN] -- If domain uses Cloudflare (varies by domain)
    | (cache miss)
    v
  [Nginx Proxy Cache] -- proxy_cache (varies by location)
    | (cache miss)
    v
  [Nginx Open File Cache] -- open_file_cache (static files only)
    | (cache miss)
    v
  [Upstream Backend] -- Node.js / Python / Next.js
```

## Cache Hit Rate Targets

| Cache Layer | Target Hit Rate | How to Measure |
|-------------|----------------|----------------|
| Browser cache (immutable assets) | 95%+ | Chrome DevTools Network tab |
| Nginx static_cache | 85-95% | $upstream_cache_status logging |
| Nginx api_cache | 40-60% | $upstream_cache_status logging |
| Nginx pages_cache | 30-50% | $upstream_cache_status logging |

## Monitoring Cache Performance

Add to nginx.conf:
```nginx
log_format cache_log '$remote_addr - $upstream_cache_status [$time_local] '
                     '"$request" $status $body_bytes_sent '
                     '"$http_referer" "$http_user_agent" '
                     'cache_key=$scheme$request_method$host$uri';

access_log /var/log/nginx/cache.log cache_log;
```

Or use nginx stub_status and Prometheus exporters to track HIT/MISS/BYPASS ratios.

## Cache Warming

For critical pages, pre-warm the cache after deploy:

```bash
#!/bin/bash
# Warm FRGCRM dashboard cache
curl -s https://frgcrm.com/api/dashboard > /dev/null
curl -s https://frgcrm.com/api/leads > /dev/null

# Warm marketing pages
curl -s https://fundsrecoverygroup.com > /dev/null
curl -s https://getsurplus.ai > /dev/null
curl -s https://surplusai.io > /dev/null

# Warm static assets
curl -s https://wheeler.frgops.io/_next/static/css/main.css > /dev/null
```
