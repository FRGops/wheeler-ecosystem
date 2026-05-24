---
name: secrets-scan
description: "Scan for secrets: gitleaks-like patterns, .env files in git, hardcoded keys, token leaks. Reports findings by severity. Never outputs actual secrets."
trigger: secrets scan, scan secrets, find secrets, secret leak, credential scan, token scan, api key scan
---

# Skill: Secrets Scan

Scan for secrets, API keys, tokens, and credentials. Reports by severity without exposing actual secret values.

## Scan Targets

### Priority 1: Configuration Files
```bash
# Find all .env files
find /opt /root -name ".env" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null

# Check permissions (world-readable secrets?)
find /opt /root -maxdepth 5 -name "*.env" -perm /o+r 2>/dev/null
find /opt /root -maxdepth 5 -name "secrets*" -perm /o+r 2>/dev/null
```

### Priority 2: Code Files
```bash
# Search for patterns (report files, never content)
rg --no-heading -l 'API[_-]?KEY|SECRET[_-]?KEY|TOKEN|PASSWORD|CREDENTIAL|AUTH_TOKEN' \
   --glob '!.git' --glob '!node_modules' --glob '!*.log' --glob '!*.pyc' \
   /opt /root 2>/dev/null | head -100
```

### Priority 3: Git History
```bash
# Check for secrets in recent commits
# (run in each tracked repo)
for repo in $(find /opt/wheeler* /opt/apps -name ".git" -maxdepth 3 -type d 2>/dev/null); do
  cd "$(dirname "$repo")"
  git log --all -20 --pretty=format:'%h %s' 2>/dev/null
done
```

### Priority 4: Docker Configs
```bash
# Check for env vars in container configs
docker inspect $(docker ps -q) --format '{{.Name}}: {{range .Config.Env}}{{.}} {{end}}' 2>/dev/null | grep -iE 'key|secret|token|password'
```

## Severity Classification

| Severity | Pattern | Action Required |
|----------|---------|-----------------|
| **CRITICAL** | Live production API key in plaintext file | Rotate immediately, remove from file |
| **HIGH** | .env in git tracking | Remove from git, add to .gitignore, chmod 600 |
| **MEDIUM** | Hardcoded credential in code comment | Extract to environment variable |
| **LOW** | Example/dummy credential | Mark clearly as non-production |

## False Positive Handling

Common false positives that should be whitelisted:
- `export NODE_ENV=production` — not a secret
- `API_KEY=your_key_here` — template placeholder
- `password: ""` — empty default
- `SECRET_KEY = os.environ.get(...)` — code fetching from env

## Output Format

```
SECRETS SCAN: <timestamp>
──────────────────────────────────────
SCANNED: <N> directories, <N> files

CRITICAL: <N>
  <file> — <description, NEVER the secret value>

HIGH: <N>
MEDIUM: <N>
LOW: <N>

FALSE POSITIVES (reviewed): <N>
──────────────────────────────────────
RESULT: [CLEAN / ISSUES FOUND — <N> require action]
ROTATION NEEDED: [YES — <N> keys / NO]
```
