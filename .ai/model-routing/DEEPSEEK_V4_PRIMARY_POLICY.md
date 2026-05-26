# DeepSeek V4 Primary Policy

## Status: ACTIVE — DO NOT MODIFY WITHOUT EXPLICIT APPROVAL

DeepSeek V4 is the **primary coding model** for the Wheeler ecosystem. All tooling, routing, and configuration must preserve this as the default.

## Protected Configuration

The following environment variables and configurations are **hands-off**:

| Item | Protection Level |
|------|-----------------|
| `ANTHROPIC_BASE_URL` | Immutable — routes to DeepSeek proxy |
| `ANTHROPIC_AUTH_TOKEN` | Immutable — DeepSeek auth token |
| `ANTHROPIC_MODEL` | Immutable — primary model selection |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Immutable |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Immutable |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Immutable |
| `DEEPSEEK_API_KEY` | Immutable |
| `LITELLM_MASTER_KEY` | Immutable |
| `~/.zshrc` | Read-only for AI agents |
| `~/.bashrc` | Read-only for AI agents |
| `~/.profile` | Read-only for AI agents |
| `~/.claude/` | Read-only for AI agents |
| Production `.env` files | Never read, never modify |
| Proxy scripts | Never modify |

## Routing Rules

1. **Default**: All coding tasks route through DeepSeek V4 via the configured proxy.
2. **Escalation**: Tasks requiring architectural reasoning or high-stakes decisions may escalate to Claude — see `ESCALATION_POLICY.md`.
3. **Never**: No agent may change the model routing configuration without explicit human approval.

## Verification

To verify DeepSeek routing is intact (presence only, no values):
```bash
for var in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL DEEPSEEK_API_KEY LITELLM_MASTER_KEY; do
  [ -n "${!var+x}" ] && echo "$var=present" || echo "$var=MISSING — ESCALATE"
done
```

## Breach Response

If DeepSeek routing is accidentally modified:
1. Do NOT attempt to fix by guessing.
2. Reference `BROKEN_DEEPSEEK_ROUTING_DO_NOT_TOUCH_RUNBOOK.md`.
3. Escalate to human immediately.
4. Do not run any further AI coding sessions until restored.
