# Human Approval Gates

## Hard Gates (ALWAYS Require Human Approval)

These gates can NEVER be bypassed by any AI agent at any autonomy level:

### 1. Production Deploy
- Any action that pushes code to a production server
- Includes: `docker compose up -d` on production, `git push main`, CI/CD deploy triggers
- Does NOT include: deploying to staging, local dev servers, test environments

### 2. Database Migrations
- Any schema change on a production database
- Includes: `prisma migrate deploy`, `alembic upgrade head`, manual SQL on production
- Does NOT include: migrations on local/dev/staging databases

### 3. Secrets Management
- Creating, rotating, or reading secrets
- Includes: API keys, database passwords, tokens, certificates
- Does NOT include: checking if an env var is present (presence only, no value)

### 4. Shell Profile Modifications
- Editing `~/.zshrc`, `~/.bashrc`, `~/.profile`, `~/.bash_profile`
- Includes: appending, replacing, or removing any lines
- Does NOT include: reading shell profiles (presence check only)

### 5. DeepSeek Routing Changes
- Modifying model routing configuration
- Includes: ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL, DEEPSEEK_API_KEY, LITELLM_MASTER_KEY
- Includes: proxy scripts, LiteLLM config, OpenRouter config
- Does NOT include: verifying env vars are present

### 6. Auth/Security/Payment Changes
- Modifying authentication or authorization logic
- Adding/changing payment flows
- Security-sensitive code paths (encryption, session management)
- Does NOT include: adding non-security middleware, logging

### 7. Major Dependency Upgrades
- Major version bumps (e.g., React 18 → 19, Python 3.11 → 3.12)
- Adding new dependencies that handle auth, security, or payments
- Removing dependency pinning
- Does NOT include: patch version bumps, dev dependency additions

### 8. Cloud Infrastructure Changes
- Terraform apply/destroy
- Kubernetes apply/delete
- Server provisioning or decommissioning
- DNS changes
- Firewall rule changes
- Does NOT include: reading infrastructure state, generating plans

### 9. GitHub Secrets / Repository Settings
- Modifying GitHub repository secrets
- Changing branch protection rules
- Modifying repository settings
- Does NOT include: reading workflow files, creating PRs

## Soft Gates (Escalate But May Proceed With Caution)

- Large refactors (> 25 files)
- Breaking API changes
- New service/module creation
- CI/CD pipeline changes
- Documentation of security procedures

## How to Request Approval

When hitting a hard gate:
1. **Stop** — do not proceed past the gate.
2. **Document** — what gate was hit, why, what's needed.
3. **Recommend** — what you would do if approved.
4. **Wait** — do not proceed until human approves.
