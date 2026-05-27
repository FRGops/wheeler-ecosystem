# Wheeler Domain Routing

## Public Domains

| Domain | App | Server | Status |
|--------|-----|--------|--------|
| fundsrecoverygroup.com | FRG Public | Hostinger | Monitor |
| www.fundsrecoverygroup.com | FRG Public | Hostinger | Monitor |
| horizonfederalservices.com | Horizon Fed | TODO | Monitor |
| predictionradar.app | Prediction Radar | TODO | Monitor |

## Checking Domains

```bash
# Quick check — all domains
wheeler domains

# Full audit
wheeler smoke all

# Individual domain
curl -sI https://fundsrecoverygroup.com
```

## SSL Monitoring

```bash
# Check SSL expiry
echo | openssl s_client -servername fundsrecoverygroup.com -connect fundsrecoverygroup.com:443 2>/dev/null | openssl x509 -noout -enddate

# via wheeler
wheeler domains  # includes SSL check
```

## Adding a Domain

1. Add to `config/domains.yml`
2. Specify app name, server, expected_public, health_path
3. Test: `wheeler domains`

## DNS Verification

```bash
dig +short fundsrecoverygroup.com
dig +short www.fundsrecoverygroup.com
dig +short horizonfederalservices.com
dig +short predictionradar.app
```
