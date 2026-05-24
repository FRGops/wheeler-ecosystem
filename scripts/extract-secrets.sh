#!/bin/bash
# Extract secrets from running Docker containers into shell-exportable env files
# This bridges the gap between Docker-stored secrets and script-required env vars

SECRETS_DIR="/opt/wheeler/secrets"
mkdir -p "$SECRETS_DIR"

# Extract from prediction-radar-app-worker (richest source of Stripe secrets)
CONTAINER=$(docker ps --format '{{.ID}}' --filter name=prediction-radar-app-worker | head -1)
if [ -n "$CONTAINER" ]; then
  docker inspect "$CONTAINER" | python3 -c "
import json, sys
data = json.load(sys.stdin)
env = data[0].get('Config',{}).get('Env',[]) or []
for e in env:
    if '=' in e:
        k, v = e.split('=', 1)
        print(f'export {k}=\"{v}\"')
" > "$SECRETS_DIR/stripe.env"
  echo "Extracted Stripe secrets from prediction-radar-app-worker"
fi

# Extract Grafana credentials
CONTAINER=$(docker ps --format '{{.ID}}' --filter name=grafana | head -1)
if [ -n "$CONTAINER" ]; then
  docker inspect "$CONTAINER" | python3 -c "
import json, sys
data = json.load(sys.stdin)
env = data[0].get('Config',{}).get('Env',[]) or []
for e in env:
    if '=' in e:
        k, v = e.split('=', 1)
        if any(s in k.upper() for s in ['GF_','GRAFANA','ADMIN']):
            print(f'export {k}=\"{v}\"')
" > "$SECRETS_DIR/grafana.env"
  echo "Extracted Grafana secrets"
fi

# Extract LiteLLM master key
CONTAINER=$(docker ps --format '{{.ID}}' --filter name=litellm | head -1)
if [ -n "$CONTAINER" ]; then
  docker inspect "$CONTAINER" | python3 -c "
import json, sys
data = json.load(sys.stdin)
env = data[0].get('Config',{}).get('Env',[]) or []
for e in env:
    if '=' in e:
        k, v = e.split('=', 1)
        if any(s in k.upper() for s in ['MASTER_KEY','LITELLM_MASTER','DATABASE_URL']):
            print(f'export {k}=\"{v}\"')
" > "$SECRETS_DIR/litellm.env"
  echo "Extracted LiteLLM secrets"
fi

# Determine Grafana API key from Grafana container
CONTAINER=$(docker ps --format '{{.ID}}' --filter name=grafana | head -1)
if [ -n "$CONTAINER" ]; then
  # Try to get API key from Grafana's internal state
  GF_SECURITY_ADMIN_PASSWORD=$(docker inspect "$CONTAINER" | python3 -c "
import json, sys
data = json.load(sys.stdin)
env = data[0].get('Config',{}).get('Env',[]) or []
for e in env:
    if '=' in e and e.split('=',1)[0] == 'GF_SECURITY_ADMIN_PASSWORD':
        print(e.split('=',1)[1])
")
  if [ -n "$GF_SECURITY_ADMIN_PASSWORD" ]; then
    # Generate a Grafana API key
    API_KEY_RESP=$(curl -s -X POST http://127.0.0.1:3002/api/auth/keys \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"wheeler-provisioning\",\"role\":\"Admin\"}" \
      -u "admin:${GF_SECURITY_ADMIN_PASSWORD}")
    GRAFANA_API_KEY=$(echo "$API_KEY_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('key',''))" 2>/dev/null)
    if [ -n "$GRAFANA_API_KEY" ]; then
      echo "export GRAFANA_API_KEY=\"${GRAFANA_API_KEY}\"" >> "$SECRETS_DIR/grafana.env"
      echo "Generated Grafana API key"
    fi
  fi
fi

# Create combined secrets file for sourcing
cat "$SECRETS_DIR"/stripe.env "$SECRETS_DIR"/grafana.env "$SECRETS_DIR"/litellm.env 2>/dev/null > "$SECRETS_DIR/all.env"

echo ""
echo "Secrets extracted to: $SECRETS_DIR/"
ls -la "$SECRETS_DIR/"
echo ""
echo "To use: source $SECRETS_DIR/all.env"
