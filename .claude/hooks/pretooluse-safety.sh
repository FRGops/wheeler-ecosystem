#!/usr/bin/env bash
# PreToolUse Hook — Safety gate before tool execution
# Blocks destructive commands, secrets access, production deployments.
# Never modifies DeepSeek routing.

TOOL_NAME="$1"
TOOL_INPUT="$2"

# Blocked tool patterns
case "$TOOL_NAME" in
  Bash)
    # Block destructive patterns
    if echo "$TOOL_INPUT" | grep -qiE 'rm -rf|sudo rm|docker system prune|docker volume prune|docker compose down -v|terraform apply|terraform destroy|kubectl delete|git push.*main|git push.*master|chmod -R|chown -R'; then
      echo "[Wheeler OS] BLOCKED: Destructive command detected"
      exit 1
    fi
    # Block .env reading
    if echo "$TOOL_INPUT" | grep -qE 'cat .*\.env|read .*\.env|grep .*\.env|secrets/'; then
      echo "[Wheeler OS] BLOCKED: .env/secrets access detected"
      exit 1
    fi
    # Block shell profile modification
    if echo "$TOOL_INPUT" | grep -qE '(~/.zshrc|~/.bashrc|~/.profile|~/.bash_profile).*>>|tee.*(~/.zshrc|~/.bashrc|~/.profile)'; then
      echo "[Wheeler OS] BLOCKED: Shell profile modification detected"
      exit 1
    fi
    # Block DeepSeek routing changes
    if echo "$TOOL_INPUT" | grep -qiE '(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|DEEPSEEK_API_KEY|LITELLM_MASTER_KEY).*='; then
      echo "[Wheeler OS] BLOCKED: Model routing modification detected"
      exit 1
    fi
    ;;
esac

# Allow all other tools
exit 0
