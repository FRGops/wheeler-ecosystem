# =============================================================================
# TEMPLATE — DO NOT APPLY WITHOUT REVIEW
# =============================================================================
# Cloudflare DNS cutover checklist for Wheeler ecosystem 3-server migration.
#
# Use this document as a step-by-step runbook when you are ready to point
# revenue-critical domains at the new infrastructure. Every checkbox must be
# verified before you press "Save" in the Cloudflare dashboard.
# =============================================================================

---

## 1. PRE-FLIGHT — Before touching any DNS record

### 1.1 Gather current DNS state
- [ ] Export full DNS zone for every domain from Cloudflare dashboard
  (My Profile → Export). Store exports in a safe location.
- [ ] For each domain below, record the **current A record** value:

| Domain                                   | Current A/CNAME Target | Orange/Gray |
|------------------------------------------|------------------------|-------------|
| `fundsrecoverygroup.com`                 |                        |             |
| `predictionradar.app`                    |                        |             |
| `surplusai.io`                           |                        |             |
| `frgops.fundsrecoverygroup.tech`         |                        |             |
| `radar.fundsrecoverygroup.tech`          |                        |             |
| `wheeler.frgop.io`                       |                        |             |

- [ ] Record current SSL/TLS mode per domain: _______

### 1.2 Verify new targets are reachable
- [ ] From a machine **outside** the Tailscale mesh, curl the new EDGE IP
  (187.77.148.88) on port 443 with the correct Host header and verify a 200:
  ```
  curl -I -k --resolve "fundsrecoverygroup.com:443:187.77.148.88" \
       https://fundsrecoverygroup.com/health
  ```
- [ ] Repeat for each domain in the table above.

### 1.3 Pre-provision SSL certificates
- [ ] Confirm Cloudflare Origin CA certificate is installed on the EDGE
  Traefik for every domain (or Let's Encrypt / ACME is functioning).
- [ ] Verify certificate expiry dates: `echo | openssl s_client -connect 187.77.148.88:443 -servername <domain> 2>/dev/null | openssl x509 -noout -dates`

### 1.4 Prepare rollback file
- [ ] Create a text file `/root/configs/rollback-dns-YYYYMMDD.md` containing
  the **exact current state** of every record you are about to change. See
  Section 7 below for the rollback template.

---

## 2. CLOUDFLARE SSL/TLS MODE — per domain

> Recommended final state: **Full (strict)**. This mode requires a valid CA-
> signed certificate on the origin server. If using a self-signed cert,
> fall back to **Full** (not strict) but NEVER use **Flexible** — it
> encrypts only browser ↔ Cloudflare, NOT Cloudflare ↔ origin.

| Domain                                   | Current Mode | Target Mode |
|------------------------------------------|-------------|-------------|
| `fundsrecoverygroup.com`                 |             | Full (strict)|
| `predictionradar.app`                    |             | Full (strict)|
| `surplusai.io`                           |             | Full (strict)|
| `frgops.fundsrecoverygroup.tech`         |             | Full (strict)|
| `radar.fundsrecoverygroup.tech`          |             | Full (strict)|
| `wheeler.frgop.io`                       |             | Full (strict)|

- [ ] If changing from **Flexible** → **Full (strict)**, first verify the
  origin presents a valid certificate (see 1.3). Change mode **before**
  switching the A record to avoid a certificate mismatch outage window.
- [ ] Confirm **Always Use HTTPS** is ON for every domain.
- [ ] Confirm **Minimum TLS Version** is set to 1.2 or higher.

---

## 3. DNS RECORD AUDIT — per domain

### 3.1 `fundsrecoverygroup.com`
| Type  | Name     | Value                  | TTL   | Proxy | Notes |
|-------|----------|------------------------|-------|-------|-------|
| A     | @        |                        | 300   | 🟠    | Root  |
| A     | www      |                        | 300   | 🟠    | WWW   |
| CNAME | *        |                        | 300   | 🟠    | Wildcard (if used) |
| TXT   | @        | v=spf1 ...             | auto  | —     | Email  |
| MX    | @        |                        | auto  | —     | Email  |

- [ ] **CRITICAL**: If email (MX) is hosted externally (Google Workspace,
  O365, etc.), the MX record MUST NOT be proxied through Cloudflare (keep
  it **gray cloud** / DNS-only). Proxying MX through Cloudflare breaks
  email delivery.
- [ ] DMARC, DKIM, SPF TXT records preserved and unproxied.

### 3.2 `predictionradar.app`
| Type  | Name     | Value                  | TTL   | Proxy | Notes |
|-------|----------|------------------------|-------|-------|-------|
| A     | @        |                        | 300   | 🟠    |       |
| A     | www      |                        | 300   | 🟠    |       |

- [ ] CAA record (if any) allows Let's Encrypt / Cloudflare Origin CA.

### 3.3 `surplusai.io`
| Type  | Name     | Value                  | TTL   | Proxy | Notes |
|-------|----------|------------------------|-------|-------|-------|
| A     | @        |                        | 300   | 🟠    |       |
| A     | www      |                        | 300   | 🟠    |       |

### 3.4 `frgops.fundsrecoverygroup.tech`
| Type  | Name     | Value                  | TTL   | Proxy | Notes |
|-------|----------|------------------------|-------|-------|-------|
| A     | @        |                        | 300   | 🟠    |       |

### 3.5 `radar.fundsrecoverygroup.tech`
| Type  | Name     | Value                  | TTL   | Proxy | Notes |
|-------|----------|------------------------|-------|-------|-------|
| CNAME | radar    |                        | 300   | 🟠    |       |

### 3.6 `wheeler.frgop.io`
| Type  | Name     | Value                  | TTL   | Proxy | Notes |
|-------|----------|------------------------|-------|-------|-------|
| CNAME | wheeler  |                        | 300   | 🟠    |       |

---

## 4. ORANGE CLOUD vs GRAY CLOUD — Decision Matrix

| Scenario                                      | Use This   | Why |
|-----------------------------------------------|------------|-----|
| Public web traffic (browsers, APIs)           | 🟠 Orange  | DDoS protection, CDN caching, IP masking |
| Email (MX records)                            | ⬜ Gray    | Cloudflare proxy does not speak SMTP |
| SSH / SFTP (port 22)                          | ⬜ Gray    | Cloudflare proxy only supports HTTP/HTTPS |
| Git / rsync                                   | ⬜ Gray    | Only HTTP/HTTPS proxied |
| Tailscale subnet route (non-HTTP)             | ⬜ Gray    | Proxy breaks the WireGuard handshake |
| Database replication (port 5432/3306)         | ⬜ Gray    | Not proxied by Cloudflare; use Tailscale |
| Health-check endpoints (origin status)        | 🟠 Orange  | Keep it behind Cloudflare so WAF rules apply |
| Static assets (JS, CSS, images)               | 🟠 Orange  | Cache at edge, reduce origin load |
| Admin / internal dashboards                   | 🟠 Orange  | Add IP allow-list WAF rule for extra safety |

- [ ] For **every** A/AAAA/CNAME record changed today, verify the proxy
  toggle is set correctly per the matrix above.

---

## 5. PAGE RULES & WAF RULE AUDIT

### 5.1 Page Rules (if any)
> Page Rules are evaluated in order; number them accordingly.

| # | Domain / Pattern            | Action                   | Status |
|---|-----------------------------|--------------------------|--------|
| 1 |                             |                          |        |
| 2 |                             |                          |        |

- [ ] Confirm no Page Rule accidentally rewrites the origin hostname to the
  old server.
- [ ] Cache-level rule for static assets (`*.css`, `*.js`, `*.png`, etc.).

### 5.2 WAF / Firewall Rules
| Rule Name            | Expression                          | Action       | Enabled |
|----------------------|-------------------------------------|--------------|---------|
| Block non-US IPs     | `ip.geoip.country ne "US"`         | Block        | [ ]     |
| Rate-limit login     | `http.request.uri.path eq "/login"` | Rate Limit   | [ ]     |
| Allow health checks  | `http.request.uri.path eq "/health"`| Allow        | [ ]     |
| Managed rules (OWASP)| —                                   | Log / Block  | [ ]     |

- [ ] Review every WAF rule to ensure the new origin IP or hostname is not
  inadvertently blocked.

---

## 6. DNS PROPAGATION VERIFICATION STEPS

> TTL on A/CNAME records should be dropped to 60–300 seconds **at least
> 1 TTL period** before the cutover to minimize the propagation window.

### 6.1 Pre-cutover (TTL lowered)
- [ ] Verify new TTL is visible: `dig +short @1.1.1.1 <domain> && dig +short @8.8.8.8 <domain>`
- [ ] Check TTL value: `dig @1.1.1.1 <domain> | grep -E "^<domain>.*IN.*A"`

### 6.2 At cutover
- [ ] Update A/CNAME record in Cloudflare dashboard.
- [ ] Wait 60 seconds, then check from multiple global resolvers:
  ```
  dig +short @1.1.1.1   <domain> A
  dig +short @8.8.8.8   <domain> A
  dig +short @9.9.9.9   <domain> A
  dig +short @208.67.222.222 <domain> A
  ```
- [ ] Use `https://www.whatsmydns.net/#A/<domain>` to visually confirm
  global propagation.
- [ ] Curl each domain through Cloudflare and verify `CF-Ray` header is
  present in response (confirms traffic flows through Cloudflare proxy):
  ```
  curl -I https://<domain>/ | grep -i "cf-ray"
  ```

### 6.3 Post-cutover (after propagation confirmed)
- [ ] Raise TTL back to 3600 (1 hour) or your standard value to reduce
  query load.
- [ ] Run a full HTTP smoke-test on each domain:
  - [ ] `fundsrecoverygroup.com` → 200
  - [ ] `predictionradar.app` → 200
  - [ ] `surplusai.io` → 200
  - [ ] `frgops.fundsrecoverygroup.tech` → 200
  - [ ] `radar.fundsrecoverygroup.tech` → 200
  - [ ] `wheeler.frgop.io` → 200
- [ ] Verify SSL certificate chain (no warnings):
  ```
  curl -vI https://<domain>/ 2>&1 | grep -E "SSL|subject|issuer|expire"
  ```

---

## 7. ROLLBACK DNS CONFIGURATION TEMPLATE

> Copy this block into `/root/configs/rollback-dns-YYYYMMDD.md` and fill
> in the **current** values BEFORE making any changes.

```
## ROLLBACK — DNS Configuration as of YYYY-MM-DD HH:MM UTC

### fundsrecoverygroup.com
  A     @     CURRENT_IP    300  proxy: on
  A     www   CURRENT_IP    300  proxy: on
  MX    @     mail.provider 120  proxy: off
  TXT   @     "v=spf1 ..."

### predictionradar.app
  A     @     CURRENT_IP    300  proxy: on

### surplusai.io
  A     @     CURRENT_IP    300  proxy: on

### frgops.fundsrecoverygroup.tech
  A     @     CURRENT_IP    300  proxy: on

### radar.fundsrecoverygroup.tech
  CNAME radar CURRENT_TARGET 300 proxy: on

### wheeler.frgop.io
  CNAME wheeler CURRENT_TARGET 300 proxy: on

### SSL/TLS mode per domain (Cloudflare dashboard → SSL/TLS → Overview)
  fundsrecoverygroup.com:       _______
  predictionradar.app:          _______
  surplusai.io:                 _______
  frgops.fundsrecoverygroup.tech: _______
  radar.fundsrecoverygroup.tech:  _______
  wheeler.frgop.io:             _______

### WAF rules active (copy from dashboard → Security → WAF)
  (paste exported rules here)

### Page rules active (copy from dashboard → Rules → Page Rules)
  (paste exported rules here)
```

---

## 8. CUTOVER SEQUENCE (recommended order)

| Step | Action                                        | Rollback Time |
|------|-----------------------------------------------|---------------|
| 1    | Lower all TTLs to 60s (wait 1x old TTL)       | N/A           |
| 2    | Switch SSL/TLS mode to Full (strict) if needed | Instant       |
| 3    | Update A/CNAME records one domain at a time    | Instant       |
| 4    | Verify propagation per Section 6               | ~5 min        |
| 5    | Run full smoke-test on that domain             | ~2 min        |
| 6    | Repeat steps 3–5 for next domain               | —             |
| 7    | Raise TTLs back to 3600                        | Instant       |
| 8    | Monitor for 24h                                 | —             |

- [ ] **Never change all domains at once.** Stagger the cutover one domain
  per maintenance step so you can isolate and fix problems without taking
  down the entire ecosystem.

---

> TEMPLATE END. Fill in every blank and checkbox before cutover day.
> Store the completed, filled-in copy alongside your runbook.
> =============================================================================
