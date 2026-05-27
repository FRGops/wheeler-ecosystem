# Wheeler AI Model Routing

## Overview

The Wheeler ecosystem uses multiple AI models. The `wheeler ai` command manages routing to prevent environment variable contamination.

## Modes

### Standard Claude (Anthropic API)
```bash
wheeler ai claude
```
Uses clean Anthropic API routing. Requires:
- `ANTHROPIC_BASE_URL=https://api.anthropic.com`
- `ANTHROPIC_AUTH_TOKEN` set

### DeepSeek V4 (via LiteLLM Proxy)
```bash
wheeler ai deepseek
```
Routes through LiteLLM proxy at `:4049`. Requires:
- `ANTHROPIC_BASE_URL` pointing to LiteLLM
- `DEEPSEEK_API_KEY` set
- `LITELLM_MASTER_KEY` set
- LiteLLM running and healthy

### Kimi (Moonshot)
```bash
wheeler ai kimi
```
Uses Moonshot/Kimi API. Requires:
- `MOONSHOT_API_KEY` set

### Reset
```bash
wheeler ai reset
```
Clears ALL AI routing env vars. Prints safe `unset` commands.

## Status Check
```bash
wheeler ai status
```
Shows which AI env vars are set (never shows values). Identifies current routing mode.

## Troubleshooting

### "Invalid bearer token" or auth errors
1. Check current mode: `wheeler ai status`
2. Ensure you're not mixing Anthropic and DeepSeek vars
3. For Claude: `ANTHROPIC_BASE_URL` must be `https://api.anthropic.com`
4. For DeepSeek: LiteLLM must be running (`curl http://localhost:4049/health`)
5. Reset and re-apply: `wheeler ai reset` then `wheeler ai claude` or `wheeler ai deepseek`

### How to avoid contamination
- Only ONE set of routing vars should be active
- DeepSeek routing overrides `ANTHROPIC_BASE_URL` — reset before switching to Claude
- Use `wheeler ai reset` when switching between providers

### Cost-saving rules
- DeepSeek V4: ~10x cheaper than Claude for equivalent tasks
- Use DeepSeek for: bulk processing, drafts, internal tooling
- Use Claude for: final output, client-facing work, complex reasoning
- Monitor with: `wheeler ai status`
