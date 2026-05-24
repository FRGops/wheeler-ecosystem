# /secrets-scan — Secrets and Credential Leak Detection

Scan for secrets, API keys, tokens, and credentials in code, config, env files, and git history. Reports findings by severity without exposing actual secrets.

## Execution (ALL in parallel)

```bash
# 1. Wheeler secrets scanner
bash /opt/wheeler-ecosystem/security/secret-scan.sh 2>/dev/null

# 2. Check for .env files in git tracking
find /opt -name ".env" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null
find /root -maxdepth 3 -name ".env" -not -path "*/.git/*" 2>/dev/null

# 3. Check for common secret patterns (redacted output)
rg --no-heading -l 'API_KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL' \
   --glob '!.git' --glob '!node_modules' --glob '!*.log' \
   /opt /root 2>/dev/null | head -50

# 4. Check git history for secrets in recent commits
git -C /opt/wheeler-ecosystem log --all -20 --pretty=format:'%h %s' 2>/dev/null

# 5. Check file permissions (world-readable secrets?)
find /opt /root -maxdepth 4 -name "*.env" -perm /o+r 2>/dev/null
find /opt /root -maxdepth 4 -name "secrets*" -perm /o+r 2>/dev/null
```

## Severity Classification

| Severity | Criteria | Action |
|----------|----------|--------|
| **CRITICAL** | Live API key/token in unencrypted file | Rotate immediately, remove from git |
| **HIGH** | .env in git tracking, world-readable secrets | Remove from git, chmod 600 |
| **MEDIUM** | Password/config in code comments | Extract to secrets manager |
| **LOW** | Example/dummy credentials | Document as non-production |

## Output Format

```
╔══════════════════════════════════════════════╗
║   Secrets Scan — <timestamp>                 ║
╚══════════════════════════════════════════════╝

CRITICAL: <count>
  <file-path> — <description, NEVER the actual secret>

HIGH: <count>
  <file-path> — <description>

MEDIUM: <count>
LOW:    <count>

──────────────────────────────────────────────
SCAN RESULT: [CLEAN / ISSUES FOUND]
ROTATION NEEDED: [YES — <count> keys / NO]
```
