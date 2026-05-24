# Compression Recommendations for EDGE Server

## Current State

The global nginx.conf has `gzip on` but ALL gzip settings are COMMENTED OUT:

```nginx
gzip on;
# gzip_vary on;              # Commented
# gzip_proxied any;          # Commented
# gzip_comp_level 6;         # Commented
# gzip_buffers 16 8k;        # Commented
# gzip_http_version 1.1;     # Commented
# gzip_types ...;            # Commented
```

**Effect:** Only `text/html` (nginx default) is being compressed globally.
No other content types are compressed for proxied responses.

The wheeler-frgops-io vhost has its own gzip config (the only site that does):
```nginx
gzip on;
gzip_types text/plain text/css application/json application/javascript
           text/xml application/xml application/xml+rss text/javascript image/svg+xml;
gzip_min_length 256;
```

**24 of 25 sites are missing proper compression.**

## Target State

Enable gzip globally with all content types and proper settings, then add Brotli
as a second compression option.

## Gzip Configuration (Global)

```nginx
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 5;
gzip_min_length 256;
gzip_buffers 16 8k;
gzip_http_version 1.1;
gzip_disable "msie6";
gzip_types
    text/plain text/css text/xml text/javascript text/csv text/markdown
    application/json application/javascript application/xml application/xml+rss
    application/rss+xml application/atom+xml application/xhtml+xml
    application/ld+json application/manifest+json application/schema+json
    image/svg+xml image/x-icon image/bmp
    font/woff font/woff2 application/x-font-ttf
    application/x-font-opentype application/vnd.ms-fontobject;
```

### Gzip Compression Level Trade-off

| Level | Compression Ratio | CPU Cost | Use Case |
|-------|------------------|----------|----------|
| 1 | 50-55% reduction | Minimal | Dynamic content, high traffic |
| 3 | 60-65% reduction | Low | Balanced |
| 5 | 70-75% reduction | Moderate | General purpose (RECOMMENDED) |
| 6 | 72-77% reduction | Moderate-High | Static content |
| 9 | 75-80% reduction | High | Pre-compression only |

**Recommendation:** Level 5 for global, level 6 for pre-compressed static assets.

## Brotli Configuration (Optional, High Impact)

Brotli provides 15-20% better compression than gzip at similar CPU cost. It is
supported by all modern browsers (97%+ global coverage as of 2026).

### Installation

```bash
# Ubuntu/Debian
apt-get update && apt-get install nginx-module-brotli

# Or build from source (if module not in repos):
# apt-get install build-essential libpcre3-dev libssl-dev zlib1g-dev
# wget https://github.com/google/ngx_brotli/archive/master.zip
# Build nginx with --add-dynamic-module=../ngx_brotli
```

### Load Module (in nginx.conf, BEFORE the events block)

```nginx
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;
```

### Configuration

```nginx
brotli on;
brotli_comp_level 6;
brotli_static on;           # Serve pre-compressed .br files if present
brotli_types
    text/plain text/css text/xml text/javascript text/csv
    application/json application/javascript application/xml application/xml+rss
    application/rss+xml application/atom+xml application/xhtml+xml
    image/svg+xml
    font/woff font/woff2
    application/x-font-ttf application/x-font-opentype;
```

### Brotli Compression Level Trade-off

| Level | Compression Ratio | CPU Cost | Use Case |
|-------|------------------|----------|----------|
| 1 | 60-65% reduction | Low | Dynamic content |
| 4 | 72-77% reduction | Moderate | Balanced |
| 6 | 80-85% reduction | Moderate-High | Static content (RECOMMENDED) |
| 9 | 84-88% reduction | High | Pre-compression only |
| 11 | 86-90% reduction | Very High | Pre-compression only |

**Recommendation:** Level 6 for general use. Use level 11 for build-time pre-compression.

## Content Types That Should NOT Be Compressed

- `image/jpeg`, `image/png`, `image/gif`, `image/webp` — Already compressed formats
- `application/zip`, `application/gzip`, `application/x-rar-compressed`
- `video/*`, `audio/*`
- `application/octet-stream` with binary content
- `application/pdf` — PDFs have internal compression

## Bandwidth Savings Estimate

For a typical SPA serving 25 sites:

| Asset Type | Avg Size (Uncompressed) | After Gzip (Level 5) | After Brotli (Level 6) |
|------------|------------------------|---------------------|----------------------|
| HTML | 30 KB | 6-7 KB (78%) | 5-6 KB (82%) |
| CSS | 80 KB | 14-16 KB (81%) | 12-14 KB (84%) |
| JavaScript | 500 KB | 110-140 KB (75%) | 95-120 KB (78%) |
| JSON API | 15 KB | 2-3 KB (83%) | 2-3 KB (83%) |
| SVG icons | 10 KB | 3-4 KB (65%) | 2-3 KB (75%) |
| **Total** | **635 KB** | **135-170 KB (75%)** | **116-146 KB (79%)** |

### Monthly Bandwidth Savings (Estimated)

Assuming 100,000 page views/day with average 2MB per page:
- **Without compression:** ~200 GB/day (~6 TB/month)
- **With gzip level 5:** ~50 GB/day (~1.5 TB/month) — **75% reduction**
- **With Brotli level 6:** ~40 GB/day (~1.2 TB/month) — **80% reduction**

## Pre-Compression at Build Time

For Next.js and other JS frameworks, generate pre-compressed assets:

```bash
# Gzip pre-compression (during build)
gzip -k -9 -f dist/**/*.js dist/**/*.css dist/**/*.html

# Brotli pre-compression (during build)
brotli -Z -f dist/**/*.js dist/**/*.css dist/**/*.html
```

Nginx with `gzip_static on` and `brotli_static on` will serve these directly,
avoiding CPU cost of real-time compression.

## Testing Compression

```bash
# Test gzip
curl -s -H "Accept-Encoding: gzip" https://wheeler.frgops.io -o /dev/null -w "%{size_download}" -H "Accept-Encoding: gzip" --compressed

# Test Brotli
curl -s -H "Accept-Encoding: br" https://wheeler.frgops.io -o /dev/null -w "%{size_download}"

# Check what encoding was used
curl -sI -H "Accept-Encoding: gzip, br" https://wheeler.frgops.io | grep -i content-encoding
```
