# Broken Build Runbook

## Symptoms
- Build fails (compile errors, type errors, bundler failure)
- Tests fail
- Lint fails
- CI pipeline red

## Triage Steps

### 1. Identify What Changed
```bash
git diff --name-only HEAD~1
git log --oneline -3
```

### 2. Check If It's Environmental
```bash
node -v        # Correct version?
npm -v         # Package manager available?
python3 --version
```

### 3. Check Dependencies
```bash
# Node
ls node_modules/ 2>/dev/null && echo "node_modules exists" || echo "node_modules MISSING — run npm install"

# Python
pip list 2>/dev/null | head -5 || echo "pip not available"
```

### 4. Isolate the Failure
```bash
# Run just the failing step
npm run build 2>&1 | tail -20
npm test 2>&1 | tail -20
npm run lint 2>&1 | tail -20
```

## Common Fixes

### Missing Dependencies
```bash
npm install  # or: npm ci
```

### Type Errors
```bash
npx tsc --noEmit 2>&1 | head -30
# Fix type errors in reported files
```

### Lint Errors
```bash
npx eslint --fix .  # Auto-fix where possible
```

### Test Failures
```bash
# Run specific failing test
npm test -- -t "failing test name"
```

## When to Escalate
- Build failure caused by infrastructure (not code)
- Dependency conflict requiring major version decision
- CI environment issue (not reproducible locally)
- Build passes locally but fails in CI
