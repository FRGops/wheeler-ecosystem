# AI Session Recovery Runbook

## Symptoms
- Agent stuck in infinite loop
- Agent producing incorrect output repeatedly
- Agent modifying files it shouldn't
- Session consuming excessive tokens
- Model routing seems broken

## Recovery Procedures

### 1. Stop the Current Agent
```bash
# In Claude Code: /stop or Ctrl+C
# For background agents: find and kill
ps aux | grep claude
```

### 2. Check What Changed
```bash
git status
git diff --stat
```

### 3. Discard Unwanted Changes
```bash
# Discard changes to specific files
git restore <file>

# Discard ALL unstaged changes (CAREFUL)
git checkout .
```

### 4. Check DeepSeek Routing (presence only)
```bash
for var in ANTHROPIC_BASE_URL DEEPSEEK_API_KEY ANTHROPIC_MODEL; do
  [ -n "${!var+x}" ] && echo "$var=present" || echo "$var=MISSING"
done
```

### 5. Check Shell Profiles
```bash
# Verify no unintended modifications
git diff ~/.zshrc ~/.bashrc ~/.profile 2>/dev/null
```

### 6. Restart Session
- Close current Claude Code session
- Open new terminal
- Verify DeepSeek routing intact
- Start new session with preflight

## Prevention
- Always use AI branches (not main)
- Run preflight before significant work
- Run postflight after
- Set change budgets
- Review agent outputs before committing
