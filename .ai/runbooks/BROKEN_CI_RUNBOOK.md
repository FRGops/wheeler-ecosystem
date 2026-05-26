# Broken CI Runbook

## Symptoms
- GitHub Actions workflow failing
- CI checks stuck "in progress"
- CI reporting false failures
- CI not triggering on push/PR

## Triage

### 1. Check Workflow File
```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ai-quality-gates.yml'))" && echo "Valid YAML"
```

### 2. Check Recent Changes
```bash
git diff --name-only origin/main...HEAD | grep -E '\.github/workflows/'
```

### 3. Common Causes
- **YAML syntax error**: Validate with Python yaml module
- **Missing action version**: Check `uses:` fields have correct versions
- **Permission issue**: CI needs `contents: read` and `pull-requests: read`
- **Runner incompatibility**: `ubuntu-latest` may have changed
- **Script failure**: Test the `run:` commands locally

### 4. Run Locally (Simulate)
```bash
# Simulate what CI does
git diff --name-only origin/main...HEAD | grep -qE '^\.env' && echo "BLOCKED: .env changes" || echo "OK"

# Check for secrets
git diff origin/main...HEAD | grep -ciE '(api_key|secret|token|password)\s*=\s*[A-Za-z0-9]{20,}'
```

## Fixes

### YAML Error
- Validate YAML syntax
- Check indentation (must be spaces, not tabs)
- Verify action versions exist

### Permission Error
```yaml
permissions:
  contents: read
  pull-requests: read
```

### Stuck CI
- Cancel the stuck run in GitHub Actions UI
- Re-push to trigger a fresh run (amend commit, force push on AI branch)

## When to Escalate
- CI infrastructure issue (GitHub Actions outage)
- Runner image incompatibility
- Secrets/GitHub token issue
- Workflow requires production credentials
