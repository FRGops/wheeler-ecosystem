# Wheeler Environment Variable Standardization

**Version:** 1.0.0
**Last Updated:** 2026-05-23
**Owner:** Platform Engineering
**Scope:** All Wheeler services across all environments and deployment targets

---

## Table of Contents

1. [Philosophy & Principles](#philosophy--principles)
2. [Environment Separation](#environment-separation)
3. [Naming Standards](#naming-standards)
4. [Variable Categories](#variable-categories)
5. [File Structure & Templates](#file-structure--templates)
6. [PM2 Environment Standards](#pm2-environment-standards)
7. [Docker Environment Standards](#docker-environment-standards)
8. [Secrets Injection Standards](#secrets-injection-standards)
9. [No Duplicate Definitions Policy](#no-duplicate-definitions-policy)
10. [Centralized Config Policy](#centralized-config-policy)
11. [Validation Rules](#validation-rules)
12. [Migration Path](#migration-path)
13. [Examples & Templates](#examples--templates)

---

## Philosophy & Principles

### Core Rules (Non-Negotiable)

1. **One Source of Truth**: Every config key has exactly ONE authoritative source
2. **Never Hardcode Secrets**: Zero tolerance. Secrets come from Doppler, AWS Secrets Manager, or GPG-encrypted files
3. **No Duplicate DATABASE_URL**: The connection string pattern MUST NOT be defined in more than one place
4. **Validation Before Use**: Every .env file must pass schema validation before deployment
5. **Environment Isolation**: Production configs must NEVER be used in staging, and vice versa
6. **Auditability**: Every config change is versioned, reviewed, and logged
7. **Least Privilege**: Each service gets ONLY the variables it needs

### The Golden Rule of Config

> If you have to define the same value in two places, you have designed it wrong.
> Introduce a shared source and reference it.

---

## Environment Separation

### Environment Tiers

| Environment | Purpose                          | Data        | Access       | Config File Pattern           |
|------------|----------------------------------|-------------|-------------|-------------------------------|
| `dev`      | Local development                | Synthetic   | Developer   | `.env.dev`                    |
| `staging`  | Pre-production validation         | Anonymized  | Team + CI    | `.env.staging`                |
| `production` | Live customer-facing workloads | Real data    | CI + On-Call | `.env.production`             |
| `ci`       | CI/CD pipeline execution         | Synthetic   | CI only      | `.env.ci` (in CI secrets)     |
| `e2e`      | End-to-end test runs             | Synthetic   | CI only      | `.env.e2e`                    |

### Environment Indicator Variable

Every service MUST define:

```bash
# REQUIRED in every .env file
APP_ENV=production|staging|dev|ci|e2e
NODE_ENV=production|staging|development|test  # Node.js services only
```

The deployment scripts use `APP_ENV` to determine behavior (backup aggressiveness, health check strictness, alerting thresholds).

### Production vs Staging Differences

| Aspect              | Production                    | Staging                       |
|--------------------|-------------------------------|-------------------------------|
| Database           | Primary PostgreSQL instance   | Separate staging DB (COREDB)  |
| Redis              | Primary Redis instance (DB 0) | Staging Redis (DB 1 or separate) |
| Log Level          | `info` or `warn`              | `debug` or `info`             |
| Alerting           | Full (PagerDuty)              | Slack only                    |
| Rate Limiting      | Enforced                      | Relaxed                       |
| Backup Frequency   | Real-time + hourly            | Daily                         |
| Health Check Strict | Strict (must pass)            | Lenient                       |
| Feature Flags      | Gradual rollout               | All enabled                   |

---

## Naming Standards

### Variable Naming Convention

```
<SCOPE>_<SUBSYSTEM>_<PROPERTY>
```

**SCOPE** (Prefix):
- `APP_` — Application-level configuration
- `DB_` — Database connection parameters
- `REDIS_` — Redis connection parameters
- `AWS_` / `DO_` / `CF_` — Cloud provider-specific
- `SMTP_` — Email delivery
- `LOG_` — Logging configuration
- `AUTH_` — Authentication/authorization
- `API_` — External API configuration
- `QUEUE_` — Message queue configuration
- `CACHE_` — Caching behavior
- `FEATURE_` — Feature flags
- `DEPLOY_` — Deployment-specific metadata

**SUBSYSTEM** (optional, for clarity):
- Describes which component the variable affects
- Example: `APP_API_PORT`, `DB_PRIMARY_HOST`

**PROPERTY** (suffix):
- Describes WHAT the variable controls
- Uses UPPER_SNAKE_CASE
- No abbreviations unless universally understood (URL, API, DB, S3, AWS, JWT)

### Naming Examples

```bash
# GOOD - Clear, searchable, unambiguous
APP_NAME=wheeler-api
APP_PORT=4000
DB_PRIMARY_HOST=5.78.210.123
DB_PRIMARY_PORT=5432
DB_PRIMARY_NAME=wheeler_core
DB_PRIMARY_USER=wheeler_api
DB_PRIMARY_PASSWORD=***secret***
REDIS_URL=redis://5.78.210.123:6379/0
LOG_LEVEL=info
AUTH_JWT_SECRET=***secret***
FEATURE_ENABLE_NEW_INTAKE=true
DEPLOY_VERSION=2.4.1
DEPLOY_TIMESTAMP=2026-05-23T12:00:00Z

# BAD - Ambiguous, hard to search, inconsistent
PORT=4000                    # PORT of what?
HOST=5.78.140.118            # Which host?
DB_URL=postgresql://...      # Which DB? Ambiguous with REDIS_URL
JWT_SECRET=***secret***      # Which JWT? Auth? Internal?
FLAG_NEW_INTAKE=true         # What kind of flag?
```

### Database URL Standardization

**THE COMPOSITE URL vs INDIVIDUAL PARTS RULE:**

A service MUST use ONE of these two patterns, never both:

**Pattern A: Composite URL (preferred for single-DB services)**
```bash
DATABASE_URL=postgresql://user:pass@host:5432/dbname
```

**Pattern B: Individual Parts (preferred for multi-DB or complex setups)**
```bash
DB_PRIMARY_HOST=5.78.210.123
DB_PRIMARY_PORT=5432
DB_PRIMARY_NAME=wheeler_core
DB_PRIMARY_USER=wheeler_api
DB_PRIMARY_PASSWORD=***secret***
# Application constructs the URL from parts
```

**Pattern C: Redis URL (preferred for Redis)**
```bash
REDIS_URL=redis://:password@5.78.210.123:6379/0
# Or individual parts:
REDIS_HOST=5.78.210.123
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=***secret***
```

**CRITICAL RULE**: NEVER define both `DATABASE_URL` and individual `DB_*` parts for the same database. This causes confusion about which takes precedence.

---

## Variable Categories

### Category 1: Secrets

Variables that MUST be encrypted/injected, never stored in plain text:

```bash
# Authentication secrets
AUTH_JWT_SECRET=***
AUTH_SESSION_SECRET=***
AUTH_API_KEY_OPENAI=***
AUTH_API_KEY_ANTHROPIC=***
AUTH_API_KEY_GEMINI=***

# Database credentials
DB_PRIMARY_PASSWORD=***
DB_READONLY_PASSWORD=***
REDIS_PASSWORD=***

# Service credentials
AWS_ACCESS_KEY_ID=***
AWS_SECRET_ACCESS_KEY=***
SMTP_PASSWORD=***
STRIPE_SECRET_KEY=***
WEBHOOK_SIGNING_SECRET=***

# Encryption keys
ENCRYPTION_KEY=***
FILE_ENCRYPTION_KEY=***
```

**Injection Method**: Doppler (primary), AWS Secrets Manager (fallback), GPG-encrypted file (cold start only)

### Category 2: Configuration

Variables that define service behavior, safe in version control if not secret:

```bash
# Service identification
APP_NAME=wheeler-api
APP_PORT=4000
APP_HOST=0.0.0.0
APP_ENV=production

# Connection endpoints (non-secret parts)
DB_PRIMARY_HOST=5.78.210.123
DB_PRIMARY_PORT=5432
DB_PRIMARY_NAME=wheeler_core
REDIS_HOST=5.78.210.123
REDIS_PORT=6379

# Logging
LOG_LEVEL=info
LOG_FORMAT=json
LOG_OUTPUT=stdout

# Performance
APP_WORKERS=4
APP_MAX_MEMORY_MB=2048
APP_REQUEST_TIMEOUT_MS=30000

# External API endpoints
API_LITELLM_URL=http://localhost:5000
API_OPENCLAW_URL=http://localhost:5001
API_QDRANT_URL=http://5.78.210.123:6333
API_MINIO_URL=http://5.78.210.123:9000

# CORS
CORS_ORIGINS=https://hub.wheeler.dev,https://ops.wheeler.dev
```

### Category 3: Feature Flags

Variables that toggle features, safe in version control:

```bash
FEATURE_ENABLE_NEW_INTAKE=true
FEATURE_ENABLE_AI_ASSIST=false
FEATURE_ENABLE_REVENUE_V2=false
FEATURE_ENABLE_REALTIME_DASHBOARD=true
FEATURE_BETA_USERS_ONLY=false
FEATURE_MAINTENANCE_MODE=false
```

### Category 4: Deploy-Specific

Variables set by the deployment system, NOT manually:

```bash
DEPLOY_VERSION=2.4.1
DEPLOY_TIMESTAMP=2026-05-23T12:00:00Z
DEPLOY_COMMIT_SHA=abc123def456
DEPLOY_ENVIRONMENT=production
DEPLOY_NODE=aiops
DEPLOY_BY=ci-cd
```

---

## File Structure & Templates

### Standard Directory Layout

```
/opt/wheeler/<service>/
├── .env                    # SYMLINK to one of the below (current active)
├── .env.example            # Template with all variables documented
├── .env.production         # Actual production values (no secrets in git)
├── .env.staging            # Staging values
├── .env.dev                # Development values (safe to commit, no secrets)
├── .env.schema.json        # JSON Schema for validation
└── envs/                   # Alternative: env directory
    ├── production.env
    ├── staging.env
    └── dev.env
```

### .env.example Template Structure

```bash
# ============================================================================
# Wheeler API — Environment Configuration Template
# ============================================================================
# Service: wheeler-api
# Version: 2.4.0
# Last Updated: 2026-05-23
# ============================================================================
#
# INSTRUCTIONS:
#   1. Copy this file: cp .env.example .env.production
#   2. Fill in all values. Secrets MUST come from Doppler/AWS, not here.
#   3. Run validation: npx dotenv-schema-validator .env.production
#   4. Never commit .env.production to git.
#
# ============================================================================
# CATEGORY: Service Identification (REQUIRED)
# ============================================================================

APP_NAME=wheeler-api
APP_PORT=4000
APP_HOST=0.0.0.0
APP_ENV=production                    # production | staging | dev | ci

# ============================================================================
# CATEGORY: Database — Primary (REQUIRED)
# ============================================================================
# Use EITHER DATABASE_URL (composite) OR the individual DB_PRIMARY_* vars.
# NEVER define both for the same database.

DB_PRIMARY_HOST=5.78.210.123
DB_PRIMARY_PORT=5432
DB_PRIMARY_NAME=wheeler_core
DB_PRIMARY_USER=wheeler_api
DB_PRIMARY_PASSWORD=<FROM_DOPPLER>        # SECRET — do not hardcode

# Connection pool configuration
DB_PRIMARY_POOL_MIN=2
DB_PRIMARY_POOL_MAX=20
DB_PRIMARY_IDLE_TIMEOUT_MS=30000
DB_PRIMARY_CONNECTION_TIMEOUT_MS=10000

# ============================================================================
# CATEGORY: Redis — Cache & Sessions (REQUIRED)
# ============================================================================
# Use EITHER REDIS_URL (composite) OR individual REDIS_* vars.

REDIS_HOST=5.78.210.123
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=<FROM_DOPPLER>             # SECRET — do not hardcode

# Redis behavior
REDIS_KEY_PREFIX=wheeler:
REDIS_CONNECT_TIMEOUT_MS=5000
REDIS_COMMAND_TIMEOUT_MS=2000

# ============================================================================
# CATEGORY: External API Endpoints (REQUIRED)
# ============================================================================

API_LITELLM_URL=http://localhost:5000
API_OPENCLAW_URL=http://localhost:5001
API_QDRANT_URL=http://5.78.210.123:6333
API_MINIO_URL=http://5.78.210.123:9000

# ============================================================================
# CATEGORY: Authentication Secrets (REQUIRED)
# ============================================================================

AUTH_JWT_SECRET=<FROM_DOPPLER>            # SECRET — RSA256 private key or HMAC secret
AUTH_JWT_EXPIRY=3600                      # seconds (1 hour)
AUTH_JWT_REFRESH_EXPIRY=604800            # seconds (7 days)
AUTH_SESSION_SECRET=<FROM_DOPPLER>        # SECRET — session encryption key

# ============================================================================
# CATEGORY: External Provider API Keys (as needed)
# ============================================================================

API_KEY_OPENAI=<FROM_DOPPLER>             # SECRET
API_KEY_ANTHROPIC=<FROM_DOPPLER>          # SECRET
API_KEY_GEMINI=<FROM_DOPPLER>             # SECRET
API_KEY_SENDGRID=<FROM_DOPPLER>           # SECRET
API_KEY_STRIPE=<FROM_DOPPLER>             # SECRET

# ============================================================================
# CATEGORY: Logging Configuration
# ============================================================================

LOG_LEVEL=info                            # debug | info | warn | error
LOG_FORMAT=json                           # json | text
LOG_OUTPUT=stdout                         # stdout | file | both
LOG_FILE_PATH=/var/log/wheeler/api.log

# ============================================================================
# CATEGORY: Performance & Scaling
# ============================================================================

APP_WORKERS=4                             # Number of PM2 instances (cluster mode)
APP_MAX_MEMORY_MB=2048                    # Max heap memory in MB
APP_REQUEST_TIMEOUT_MS=30000              # Max request duration
APP_BODY_LIMIT_MB=10                      # Max request body size

# ============================================================================
# CATEGORY: CORS & Security
# ============================================================================

CORS_ORIGINS=https://hub.wheeler.dev,https://ops.wheeler.dev,https://admin.wheeler.dev
CORS_METHODS=GET,POST,PUT,PATCH,DELETE,OPTIONS
CORS_ALLOW_CREDENTIALS=true

# ============================================================================
# CATEGORY: Feature Flags
# ============================================================================

FEATURE_ENABLE_NEW_INTAKE=false
FEATURE_ENABLE_AI_ASSIST=false
FEATURE_ENABLE_REALTIME=false

# ============================================================================
# CATEGORY: Deploy Metadata (set by CI/CD, DO NOT EDIT MANUALLY)
# ============================================================================

DEPLOY_VERSION=<SET_BY_CI>
DEPLOY_TIMESTAMP=<SET_BY_CI>
DEPLOY_COMMIT_SHA=<SET_BY_CI>
```

### JSON Schema Validation File

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Wheeler API Environment Schema",
  "type": "object",
  "required": [
    "APP_NAME",
    "APP_PORT",
    "APP_ENV",
    "DB_PRIMARY_HOST",
    "DB_PRIMARY_PORT",
    "DB_PRIMARY_NAME",
    "DB_PRIMARY_USER",
    "DB_PRIMARY_PASSWORD",
    "REDIS_HOST",
    "REDIS_PORT",
    "AUTH_JWT_SECRET",
    "AUTH_SESSION_SECRET",
    "LOG_LEVEL"
  ],
  "properties": {
    "APP_NAME": { "type": "string", "pattern": "^[a-z][a-z0-9-]*$" },
    "APP_PORT": { "type": "integer", "minimum": 1024, "maximum": 65535 },
    "APP_ENV": { "type": "string", "enum": ["production", "staging", "dev", "ci", "e2e"] },
    "DB_PRIMARY_HOST": { "type": "string", "format": "hostname" },
    "DB_PRIMARY_PORT": { "type": "integer", "minimum": 1, "maximum": 65535 },
    "DB_PRIMARY_NAME": { "type": "string", "minLength": 1 },
    "DB_PRIMARY_USER": { "type": "string", "minLength": 1 },
    "DB_PRIMARY_PASSWORD": { "type": "string", "minLength": 8 },
    "REDIS_HOST": { "type": "string", "format": "hostname" },
    "REDIS_PORT": { "type": "integer", "minimum": 1, "maximum": 65535 },
    "REDIS_DB": { "type": "integer", "minimum": 0, "maximum": 15 },
    "AUTH_JWT_SECRET": { "type": "string", "minLength": 32 },
    "AUTH_SESSION_SECRET": { "type": "string", "minLength": 32 },
    "LOG_LEVEL": { "type": "string", "enum": ["debug", "info", "warn", "error"] }
  },
  "additionalProperties": false
}
```

---

## PM2 Environment Standards

### How PM2 Services Consume Environment Variables

PM2 supports two methods for providing environment variables to processes:

**Method 1: PM2 Ecosystem File (PREFERRED)**
```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    name: 'wheeler-api',
    script: './current/dist/server.js',
    cwd: '/opt/wheeler/wheeler-api',
    instances: 4,
    exec_mode: 'cluster',
    env: {
      // NON-SECRET config only
      APP_NAME: 'wheeler-api',
      APP_PORT: 4000,
      APP_ENV: 'production',
      LOG_LEVEL: 'info',
      NODE_ENV: 'production',
      // Secrets are injected via Doppler at process start
      // or loaded from encrypted .env file
    },
    env_staging: {
      APP_ENV: 'staging',
      LOG_LEVEL: 'debug',
      NODE_ENV: 'staging',
    }
  }]
};
```

**Method 2: .env File with PM2 (FALLBACK)**

To use an .env file with PM2, the application code must load it:
```javascript
// At application startup (top of server.js)
require('dotenv').config({ path: '/opt/wheeler/wheeler-api/current/.env' });
```

Or for Python:
```python
# At application startup
from dotenv import load_dotenv
load_dotenv('/opt/wheeler/wheeler-api/current/.env')
```

**PM2 env reload behavior:**
```bash
# Reload with updated env vars (from ecosystem file)
pm2 reload wheeler-api --update-env

# Start with specific env file (if app supports it)
pm2 start ecosystem.config.js --env production

# List current env for a process
pm2 env 0  # '0' is the process ID from pm2 list
```

### PM2 Environment Variable Rules

1. Non-secret variables go in `ecosystem.config.js` under `env:` block
2. Secrets NEVER go in `ecosystem.config.js` (it gets committed to git)
3. Secrets are injected via Doppler CLI at process start
4. PM2 `--update-env` flag must be used on reload to pick up config changes
5. Environment-specific overrides use `env_production:`, `env_staging:` blocks
6. Post-deploy hook in ecosystem file handles config validation

---

## Docker Environment Standards

### Docker Compose env_file Pattern

```yaml
# docker-compose.yml
services:
  changedetection:
    image: changedetection/changedetection:latest
    container_name: wheeler-changedetection
    restart: unless-stopped
    env_file:
      - .env.docker.production    # Production values (no secrets)
    environment:
      # Secrets injected from Docker secrets or external source
      - DB_PASSWORD=${DB_PASSWORD}        # From host env (Doppler-injected)
      - API_KEY=${CD_API_KEY}             # From host env (Doppler-injected)
    ports:
      - "127.0.0.1:5000:5000"
    volumes:
      - changedetection_data:/datastore
```

### Docker Environment Variable Rules

1. `.env.docker.production` contains non-secret config values
2. `environment:` block in docker-compose.yml for secrets (referenced from host env)
3. Never use `environment:` with hardcoded secret values
4. Docker Swarm secrets (if used) are the best practice for production
5. `.env` file at the docker-compose level sets variables for variable substitution ONLY
6. `env_file` sets variables INSIDE the container

### Docker Compose Secrets Pattern (Production)

```yaml
# docker-compose.production.yml
services:
  changedetection:
    image: changedetection/changedetection:latest
    env_file:
      - .env.docker.production
    secrets:
      - db_password
      - api_key
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password
      API_KEY_FILE: /run/secrets/api_key

secrets:
  db_password:
    external: true      # Created via: echo "secret" | docker secret create db_password -
  api_key:
    external: true
```

### Docker .env File (for docker-compose variable substitution)

```bash
# .docker-compose.env (at project root, used by docker-compose)
# This is ONLY for variable substitution in docker-compose.yml
# NOT passed into containers automatically

COMPOSE_PROJECT_NAME=wheeler
DOCKER_REGISTRY=registry.wheeler.dev
IMAGE_TAG=latest
DB_PASSWORD=<FROM_DOPPLER>
```

---

## Secrets Injection Standards

### Secrets Hierarchy (ordered by preference)

```
1. Doppler (PRIMARY)          — Secrets manager with CI/CD integration
2. AWS Secrets Manager        — For AWS-hosted components
3. Doppler CLI (local)        — Developer machines
4. GPG-encrypted .env file    — Cold start / disaster recovery ONLY
5. NEVER: git, hardcoded, plain-text .env files, Slack, email
```

### Doppler Integration Pattern

```bash
# CI/CD Pipeline (GitHub Actions)
- name: Inject Secrets
  uses: dopplerhq/cli-action@v2
  with:
    doppler-token: ${{ secrets.DOPPLER_SERVICE_TOKEN }}
    doppler-config: production

- name: Deploy with injected secrets
  run: |
    doppler run -- ./deployment-engine/deploy-service.sh wheeler-api production 2.4.1

# On the server (PM2 process startup)
doppler run --command "pm2 start ecosystem.config.js --env production"
```

### AWS Secrets Manager Pattern

```bash
# Retrieve secrets at deploy time
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id wheeler/production/db-password \
  --query SecretString --output text | jq -r '.password')

# Inject into PM2 process
DB_PASSWORD=$DB_PASSWORD pm2 start ecosystem.config.js --env production
```

### GPG-Encrypted Fallback (Cold Start)

```bash
# Create encrypted env file (done once, manually)
gpg --encrypt --recipient ops@wheeler.dev \
    .env.production \
    -o .env.production.gpg

# Decrypt during cold start (requires GPG key)
gpg --decrypt .env.production.gpg > .env.production
chmod 600 .env.production
source .env.production

# Shred the decrypted file after use
shred -u .env.production
```

### What NEVER Looks Like

```bash
# NEVER DO THIS - hardcoded secrets
DATABASE_URL=postgresql://admin:SuperSecret123@5.78.210.123:5432/wheeler
API_KEY=sk-abc123def456ghi789

# NEVER DO THIS - secrets in git
# File: .env (committed)
STRIPE_SECRET=sk_live_abc123

# NEVER DO THIS - secrets in ecosystem.config.js
env: {
  DB_PASSWORD: 'hunter2',  // NO!
}

# NEVER DO THIS - secrets in docker-compose.yml
environment:
  - DB_PASSWORD=hardcoded_secret  // NO!
```

---

## No Duplicate Definitions Policy

### Policy Statement

**Rule**: Each configuration key MUST have exactly ONE authoritative definition. If a value appears in multiple files, exactly ONE of them is the source of truth and the others MUST reference it.

### How Duplicates Happen (and How to Fix)

**Problem: DATABASE_URL defined in .env AND ecosystem.config.js AND docker-compose.yml**

```bash
# BAD — three definitions, which one wins?
# .env.production
DATABASE_URL=postgresql://user:pass@5.78.210.123:5432/wheeler_core

# ecosystem.config.js
env: {
  DATABASE_URL: 'postgresql://user:pass@5.78.210.123:5432/wheeler_core'  // DUPLICATE!
}

# docker-compose.yml
environment:
  - DATABASE_URL=postgresql://user:pass@5.78.210.123:5432/wheeler_core  // DUPLICATE!
```

**Solution: Single source of truth**

```bash
# .env.production — the ONE source of truth
DATABASE_URL=postgresql://user:pass@5.78.210.123:5432/wheeler_core

# ecosystem.config.js — reference the file, don't redefine
// Application code loads .env via require('dotenv').config()

# docker-compose.yml — reference host env, don't redefine
environment:
  - DATABASE_URL=${DATABASE_URL}  # References host environment variable
```

### Duplicate Detection

The `preflight-check.sh` script automatically detects duplicates:

```bash
# Checks for DATABASE_URL in multiple places
# Checks for REDIS_URL in multiple places
# Checks for any AWS_* key duplicated
# Fails preflight if duplicates found
```

---

## Centralized Config Policy

### Single Source of Truth Per Category

| Config Category    | Source of Truth              | How Services Access It            |
|-------------------|------------------------------|----------------------------------|
| Database endpoints | `/opt/wheeler/configs/shared/database.yaml` | Symlinked or injected at deploy |
| Redis endpoints    | `/opt/wheeler/configs/shared/redis.yaml`    | Symlinked or injected at deploy |
| API keys           | Doppler                       | Doppler CLI at runtime           |
| Feature flags      | `/opt/wheeler/configs/shared/features.yaml` | Loaded at app startup           |
| Service endpoints  | `/opt/wheeler/configs/shared/services.yaml` | Loaded at app startup           |
| Deploy metadata    | CI/CD pipeline                | Injected as DEPLOY_* vars        |

### Shared Configuration Files

```yaml
# /opt/wheeler/configs/shared/database.yaml
# ONE source of truth for all database connections
postgresql:
  primary:
    host: 5.78.210.123
    port: 5432
    name: wheeler_core
    user: wheeler_api
    # password: via Doppler
  analytics:
    host: 5.78.210.123
    port: 5432
    name: wheeler_analytics
    user: wheeler_analytics
    # password: via Doppler

redis:
  primary:
    host: 5.78.210.123
    port: 6379
    db: 0
    # password: via Doppler
```

```yaml
# /opt/wheeler/configs/shared/services.yaml
# ONE source of truth for internal service endpoints
services:
  litellm:
    host: localhost
    port: 5000
  openclaw:
    host: localhost
    port: 5001
  qdrant:
    host: 5.78.210.123
    port: 6333
  minio:
    host: 5.78.210.123
    port: 9000
```

### Config Consumption

Services load the shared config at startup:

```javascript
// Node.js
const { loadSharedConfig } = require('@wheeler/shared-config');
const config = loadSharedConfig();

const dbUrl = `postgresql://${config.database.user}:${process.env.DB_PASSWORD}@${config.database.host}:${config.database.port}/${config.database.name}`;
```

```python
# Python
from wheeler_shared_config import load_config

config = load_config()
db_url = f"postgresql://{config['database']['user']}:{os.environ['DB_PASSWORD']}@{config['database']['host']}:{config['database']['port']}/{config['database']['name']}"
```

---

## Validation Rules

### What Gets Validated

The `preflight-check.sh` script performs these validations:

1. **Syntax**: .env file is valid shell syntax (no unclosed quotes, valid assignments)
2. **Required Variables**: All REQUIRED vars from .env.schema.json are present
3. **Type Checking**: Ports are integers, URLs are valid, enums match allowed values
4. **No Duplicates**: Same key not defined in multiple places
5. **No Hardcoded Secrets**: Scans for patterns like `password=`, `secret=`, `key=sk-`
6. **Production Safety**: Production env has LOG_LEVEL=info or higher
7. **Port Conflicts**: Port is not already in use
8. **Host Reachability**: Database, Redis hosts are reachable
9. **Format**: .env file ends with newline, no trailing whitespace

### Validation Command

```bash
# Validate a specific env file
./deployment-engine/preflight-check.sh wheeler-api production

# Validate all services before a release
./deployment-engine/preflight-check.sh --all production
```

### Validation Output

```
=== Pre-flight Check: wheeler-api / production ===

[PASS] Syntax validation — .env.production is valid
[PASS] Required variables — all 9 required vars present
[PASS] Type checking — all ports are valid integers
[PASS] No duplicates — no duplicate definitions found
[PASS] No hardcoded secrets — no plain-text secrets detected
[PASS] Production safety — LOG_LEVEL=info (not debug)
[PASS] Port 4000 — available
[PASS] Host 5.78.210.123 — reachable (postgresql:5432)
[PASS] Host 5.78.210.123 — reachable (redis:6379)
[PASS] Format — file ends with newline

Result: ALL CHECKS PASSED (10/10)
```

---

## Migration Path

### Current State Assessment

Existing Wheeler services may have:
- Hardcoded configs in application code
- Mixed .env and ecosystem.config.js definitions
- Duplicate DATABASE_URL definitions
- Secrets in plain-text .env files
- No validation
- Inconsistent naming conventions

### Migration Phases

**Phase 1: Inventory (Week 1)**
```bash
# Audit all existing env files
find /opt/wheeler -name ".env*" -o -name "ecosystem.config.js" -o -name "docker-compose*.yml"

# Generate report of all variables in use
./deployment-engine/preflight-check.sh --audit-all
```

**Phase 2: Standardize Names (Week 1-2)**
- Rename variables to match naming conventions
- Update application code to use new names
- Keep backward compatibility (read both old and new names) during transition

**Phase 3: Extract Secrets (Week 2)**
- Move all secrets to Doppler
- Remove secrets from .env files
- Add `.env.*` to .gitignore if not already
- Rotate all exposed secrets

**Phase 4: Centralize Shared Config (Week 2-3)**
- Create `/opt/wheeler/configs/shared/` with canonical configs
- Update services to load from shared config
- Remove duplicate endpoint definitions

**Phase 5: Add Validation (Week 3)**
- Create `.env.schema.json` for each service
- Add validation to CI/CD pipeline
- Add validation to pre-commit hooks

**Phase 6: Enforce Policy (Week 4+)**
- Preflight check runs on every deploy
- Deploy blocked if validation fails
- Automated duplicate detection
- Regular config drift audits

### Backward Compatibility

During migration, services should support both old and new variable names:

```javascript
// Transitional code — remove after migration is complete
const dbHost = process.env.DB_PRIMARY_HOST || process.env.DB_HOST || 'localhost';
const dbPort = process.env.DB_PRIMARY_PORT || process.env.DB_PORT || 5432;
```

---

## Examples & Templates

### Complete .env.production Example (wheeler-api)

```bash
# ============================================================================
# Wheeler API — Production Environment Configuration
# ============================================================================
# Service: wheeler-api | Node: AIOPS (5.78.140.118) | Port: 4000
# Generated: 2026-05-23 | Template Version: 2.4.0
# ============================================================================

APP_NAME=wheeler-api
APP_PORT=4000
APP_HOST=0.0.0.0
APP_ENV=production
NODE_ENV=production

DB_PRIMARY_HOST=5.78.210.123
DB_PRIMARY_PORT=5432
DB_PRIMARY_NAME=wheeler_core
DB_PRIMARY_USER=wheeler_api
DB_PRIMARY_PASSWORD=<FROM_DOPPLER:wheeler/production/DB_PRIMARY_PASSWORD>
DB_PRIMARY_POOL_MIN=4
DB_PRIMARY_POOL_MAX=40
DB_PRIMARY_IDLE_TIMEOUT_MS=30000
DB_PRIMARY_CONNECTION_TIMEOUT_MS=10000

REDIS_HOST=5.78.210.123
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=<FROM_DOPPLER:wheeler/production/REDIS_PASSWORD>
REDIS_KEY_PREFIX=wheeler:
REDIS_CONNECT_TIMEOUT_MS=5000
REDIS_COMMAND_TIMEOUT_MS=2000

API_LITELLM_URL=http://localhost:5000
API_OPENCLAW_URL=http://localhost:5001
API_QDRANT_URL=http://5.78.210.123:6333
API_MINIO_URL=http://5.78.210.123:9000

AUTH_JWT_SECRET=<FROM_DOPPLER:wheeler/production/AUTH_JWT_SECRET>
AUTH_JWT_EXPIRY=3600
AUTH_JWT_REFRESH_EXPIRY=604800
AUTH_SESSION_SECRET=<FROM_DOPPLER:wheeler/production/AUTH_SESSION_SECRET>

API_KEY_OPENAI=<FROM_DOPPLER:wheeler/production/API_KEY_OPENAI>
API_KEY_ANTHROPIC=<FROM_DOPPLER:wheeler/production/API_KEY_ANTHROPIC>
API_KEY_SENDGRID=<FROM_DOPPLER:wheeler/production/API_KEY_SENDGRID>
API_KEY_STRIPE=<FROM_DOPPLER:wheeler/production/API_KEY_STRIPE>

LOG_LEVEL=info
LOG_FORMAT=json
LOG_OUTPUT=stdout

APP_WORKERS=4
APP_MAX_MEMORY_MB=2048
APP_REQUEST_TIMEOUT_MS=30000
APP_BODY_LIMIT_MB=10

CORS_ORIGINS=https://hub.wheeler.dev,https://ops.wheeler.dev,https://admin.wheeler.dev,https://portal.wheeler.dev
CORS_METHODS=GET,POST,PUT,PATCH,DELETE,OPTIONS
CORS_ALLOW_CREDENTIALS=true

FEATURE_ENABLE_NEW_INTAKE=false
FEATURE_ENABLE_AI_ASSIST=true
FEATURE_ENABLE_REALTIME=true

DEPLOY_VERSION=<SET_BY_CI>
DEPLOY_TIMESTAMP=<SET_BY_CI>
DEPLOY_COMMIT_SHA=<SET_BY_CI>
```

### PM2 Ecosystem File Example (with env separation)

```javascript
// /opt/wheeler/wheeler-api/ecosystem.config.js
module.exports = {
  apps: [{
    name: 'wheeler-api',
    script: './current/dist/server.js',
    cwd: '/opt/wheeler/wheeler-api',
    instances: 4,
    exec_mode: 'cluster',
    max_memory_restart: '2048M',
    kill_timeout: 30000,
    listen_timeout: 10000,
    wait_ready: true,
    shutdown_with_message: true,

    // Non-secret config only — secrets come from Doppler at runtime
    env: {
      APP_NAME: 'wheeler-api',
      APP_PORT: 4000,
      APP_HOST: '0.0.0.0',
      LOG_LEVEL: 'info',
      NODE_ENV: 'production',
      APP_WORKERS: '4',
    },

    env_staging: {
      APP_ENV: 'staging',
      LOG_LEVEL: 'debug',
      NODE_ENV: 'staging',
      APP_WORKERS: '2',
    },

    env_dev: {
      APP_ENV: 'dev',
      LOG_LEVEL: 'debug',
      NODE_ENV: 'development',
      APP_WORKERS: '1',
    },

    // Deployment hooks
    post_deploy: 'npm ci --production && pm2 reload ecosystem.config.js --update-env',
  }]
};
```

### Docker Compose Example (with env separation)

```yaml
# /opt/wheeler/changedetection/docker-compose.yml
version: '3.8'

services:
  changedetection:
    image: ${DOCKER_REGISTRY:-ghcr.io}/changedetection/changedetection:${IMAGE_TAG:-latest}
    container_name: wheeler-changedetection
    restart: unless-stopped
    env_file:
      - .env.docker.${APP_ENV:-production}
    environment:
      - DB_PASSWORD=${DB_PASSWORD}
      - API_KEY=${CD_API_KEY}
    ports:
      - "127.0.0.1:${CD_PORT:-5000}:5000"
    volumes:
      - changedetection_data:/datastore
      - ./configs:/app/configs:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  changedetection_data:
    external: true
    name: wheeler_changedetection_data

networks:
  default:
    name: wheeler_aiops
    external: true
```

---

## Appendix: Quick Reference

### Environment Variable Checklist (per service)

- [ ] APP_NAME defined and consistent with service catalog
- [ ] APP_ENV set correctly
- [ ] Database credentials use <FROM_DOPPLER> placeholder (or individual DB_* vars)
- [ ] Redis credentials use <FROM_DOPPLER> placeholder
- [ ] No hardcoded passwords, API keys, or secrets
- [ ] No duplicate DATABASE_URL or REDIS_URL definitions
- [ ] .env.example exists and is up to date
- [ ] .env.schema.json exists and is valid
- [ ] .env.production is in .gitignore
- [ ] ecosystem.config.js has no secrets (PM2 services only)
- [ ] docker-compose.yml has no hardcoded secrets (Docker services only)
- [ ] All variable names follow UPPER_SNAKE_CASE
- [ ] Feature flags start with FEATURE_
- [ ] Deploy metadata variables exist (DEPLOY_VERSION, etc.)
- [ ] Validation passes: preflight-check.sh <service> <env>

### Command Quick Reference

```bash
# Validate env for a service
./deployment-engine/preflight-check.sh wheeler-api production

# Deploy with Doppler secrets
doppler run -- ./deployment-engine/deploy-service.sh wheeler-api production 2.4.1

# Regenerate .env.example from schema
npx dotenv-schema-generator .env.schema.json > .env.example

# Audit all env files across all services
./deployment-engine/preflight-check.sh --audit-all

# Check for hardcoded secrets in all files
grep -r "PASSWORD=\|SECRET=\|API_KEY=" /opt/wheeler --include="*.env*" --include="*.yml" --include="*.js" | grep -v "FROM_DOPPLER" | grep -v ".example"
```
