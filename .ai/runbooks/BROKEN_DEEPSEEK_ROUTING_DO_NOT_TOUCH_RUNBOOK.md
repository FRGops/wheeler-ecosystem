# Broken DeepSeek Routing — DO NOT TOUCH Runbook

## CRITICAL: Read First

If you suspect DeepSeek routing is broken, DO NOT attempt to fix it yourself. Incorrect fixes can make the problem worse and lock you out of AI-assisted coding entirely.

## Symptoms of Routing Issues
- Claude Code using wrong model
- API errors when making requests
- "Model not found" errors
- Authentication failures
- Unexpected rate limits
- Responses from unexpected models

## IMMEDIATE ACTIONS

### 1. Verify Presence (Never Values)
```bash
for var in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL DEEPSEEK_API_KEY LITELLM_MASTER_KEY; do
  if [ -n "${!var+x}" ]; then echo "$var=present"; else echo "$var=MISSING"; fi
done
```

### 2. Check Proxy Health
```bash
# Check if LiteLLM proxy is running (presence only)
curl -s -o /dev/null -w "%{http_code}" http://localhost:4049/health 2>/dev/null || echo "LiteLLM not reachable"
```

### 3. Document What Changed Recently
```bash
git log --oneline -5
git diff --name-only HEAD~1
```

## WHAT NOT TO DO
- DO NOT unset or modify environment variables
- DO NOT edit ~/.zshrc or ~/.bashrc
- DO NOT restart proxy servers
- DO NOT change API keys
- DO NOT modify Claude Code settings
- DO NOT reinstall Claude Code
- DO NOT run any "fix" scripts you find online

## WHAT TO DO
1. Document: what's the exact error message?
2. Document: what was the last thing that worked?
3. Check: did anyone/something modify shell configs?
4. Check: is the LiteLLM proxy running?
5. Escalate to human with findings above

## Emergency Fallback
If you need to code NOW and DeepSeek is down:
- Use Claude Code directly (not through DeepSeek proxy)
- This requires changing ANTHROPIC_BASE_URL — document and get approval first
- Restore DeepSeek routing as soon as possible

## Recovery Checklist
- [ ] All env vars present
- [ ] Proxy responding
- [ ] Shell configs unchanged
- [ ] Claude Code settings unchanged
- [ ] Test request succeeds
