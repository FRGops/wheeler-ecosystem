#!/usr/bin/env bash
# ============================================
# audit-domains.sh — Domain health audit
# ============================================
set -euo pipefail

REPORT_DIR="$HOME/WheelerCommandCenter/reports/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/audit-domains.txt"

DOMAINS=(
  "fundsrecoverygroup.com"
  "www.fundsrecoverygroup.com"
  "horizonfederalservices.com"
  "predictionradar.app"
)

{
  echo "=== Wheeler Domain Audit ==="
  echo "Date: $(date)"
  echo ""

  for domain in "${DOMAINS[@]}"; do
    echo "--- $domain ---"

    # DNS
    IP=$(dig +short "$domain" 2>/dev/null | head -1)
    if [ -n "$IP" ]; then
      echo "  DNS: $IP"
    else
      echo "  DNS: [FAIL] not resolving"
    fi

    # HTTP
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -L "http://$domain" 2>/dev/null || echo "000")
    echo "  HTTP: $HTTP_CODE"

    # HTTPS
    HTTPS_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -L "https://$domain" 2>/dev/null || echo "000")
    echo "  HTTPS: $HTTPS_CODE"

    # SSL
    if command -v openssl &>/dev/null; then
      SSL_END=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
      if [ -n "$SSL_END" ]; then
        echo "  SSL expires: $SSL_END"
      else
        echo "  SSL: [WARN] Could not check"
      fi
    fi
    echo ""
  done

  echo "=== Audit Complete ==="
} > "$REPORT" 2>&1

echo "Report saved: $REPORT"
cat "$REPORT"
