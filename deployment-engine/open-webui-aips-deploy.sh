#!/bin/bash
# Deploy Open WebUI on AIOPS behind Tailscale
# Uses AIOPS LiteLLM for LLM access
set -e

AIOPS_HOST="5.78.140.118"
AIOPS_TS="100.121.230.28"

echo "=== Deploying Open WebUI on AIOPS ==="

ssh root@$AIOPS_HOST "bash -s" << 'ENDSSH'
set -e

# Create directory
mkdir -p /opt/open-webui/data
cd /opt/open-webui

# Create docker-compose
cat > docker-compose.yml << 'COMPOSE'
version: '3.8'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:8080"
    volumes:
      - ./data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://host.docker.internal:11434
      - WEBUI_AUTH=true
      - ENABLE_OLLAMA_API=true
      - ENABLE_OPENAI_API=true
      - OPENAI_API_BASE_URL=http://100.121.230.28:4049/v1
      - OPENAI_API_KEY=sk-litellm-909eb5abee92798032c9528b3159f4ec3c6d3603e5b3e922
      - WEBUI_SECRET_KEY=cc85ddbb40e18d7e5a7b12466b6182cbbaafd1d77dcbbe2e71b85760f1ad1069
      - DEFAULT_MODELS=deepseek-chat
    extra_hosts:
      - "host.docker.internal:host-gateway"
COMPOSE

echo "docker-compose.yml created"

# Pull and start
docker compose pull
docker compose up -d

echo "Waiting for startup..."
sleep 5
docker ps --filter name=open-webui --format '{{.Names}} {{.Status}}'
curl -s -o /dev/null -w "Health: %{http_code}\n" http://localhost:3000/

echo "=== Open WebUI deployed on AIOPS ==="
ENDSSH
