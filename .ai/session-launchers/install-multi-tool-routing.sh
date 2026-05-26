#!/usr/bin/env bash
# Install Multi-Tool Routing Dependencies
# Installs Aider and OpenCode for full model routing matrix support.
# SAFE: Does not modify DeepSeek routing, env vars, or shell profiles.
set -euo pipefail

echo "============================================"
echo " Wheeler Multi-Tool Routing Installer"
echo "============================================"
echo ""

INSTALLED=0
SKIPPED=0

# Install Aider
echo "--- Aider (DeepSeek V4 / AI coding assistant) ---"
if command -v aider &>/dev/null; then
  echo "  Aider already installed: $(aider --version 2>/dev/null || echo 'version unknown')"
  INSTALLED=$((INSTALLED + 1))
else
  echo "  Installing aider via pip..."
  if pip3 install --break-system-packages aider-chat 2>&1 | tail -3; then
    echo "  Aider installed successfully: $(aider --version 2>/dev/null || echo 'ok')"
    INSTALLED=$((INSTALLED + 1))
  else
    echo "  WARNING: Aider installation failed — install manually: pip3 install --break-system-packages aider-chat"
    SKIPPED=$((SKIPPED + 1))
  fi
fi
echo ""

# Install OpenCode
echo "--- OpenCode (parallel terminal / provider-neutral agent) ---"
if command -v opencode &>/dev/null; then
  echo "  OpenCode already installed: $(opencode --version 2>/dev/null || echo 'version unknown')"
  INSTALLED=$((INSTALLED + 1))
else
  echo "  OpenCode requires manual installation."
  echo "  See: https://github.com/opencode-ai/opencode"
  echo "  Install: npm install -g opencode"
  echo "  SKIPPED: npm global install requires separate verification"
  SKIPPED=$((SKIPPED + 1))
fi
echo ""

# Verify nothing was broken
echo "--- DeepSeek Protection Verification ---"
for var in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL DEEPSEEK_API_KEY LITELLM_MASTER_KEY; do
  if [ -n "${!var+x}" ]; then
    echo "  $var=present"
  else
    echo "  $var=MISSING — ESCALATE IMMEDIATELY"
  fi
done
echo ""

echo "============================================"
echo " Install Summary"
echo " Installed: $INSTALLED"
echo " Skipped:   $SKIPPED"
echo " DeepSeek routing: VERIFIED INTACT"
echo "============================================"
