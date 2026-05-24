#!/usr/bin/env bash
# ==============================================================================
# env-template.sh — Environment variable template generator
# ==============================================================================
#
# Creates and manages .env files from templates. Validates required variables,
# generates secure random passwords for new deployments, and stores everything
# in /opt/wheeler/config/envs/ with strict permissions (600).
#
# Usage:
#   ./env-template.sh <app-name>                    # Create .env from template
#   ./env-template.sh <app-name> --init             # Create with secure defaults
#   ./env-template.sh <app-name> --validate         # Check required vars exist
#   ./env-template.sh <app-name> --show             # Display (with value masking)
#   ./env-template.sh --list                        # List all .env files
#
# Examples:
#   ./env-template.sh prediction-radar --init       # Create fresh .env
#   ./env-template.sh ravynai --validate            # Check all required vars
#   ./env-template.sh --list                        # Show all env files
#
# Twelve-Factor App Compliance:
#   All configuration is stored in environment variables. No hardcoded config
#   in application code. This script enforces that pattern.
#
# Security:
#   - Environment files stored with chmod 600 (owner read/write only)
#   - Secrets are never displayed in plain text (masked)
#   - Auto-generated passwords use 64 chars of cryptographic randomness
#   - File ownership set to root (or deploying user)
# ==============================================================================

set -euo pipefail

# --- Globals -----------------------------------------------------------------
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
ENVS_DIR="${BASE_DIR}/config/envs"
TEMPLATE_DIR="."  # Look for .env.example files here

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Known application templates (built-in) ----------------------------------
# Format: "VAR1:description:default|VAR2:description:default|..."
# Default can be "auto" to auto-generate, "required" for mandatory user input

declare -A APP_TEMPLATES

APP_TEMPLATES["prediction-radar"]='DATABASE_URL:PostgreSQL connection URL:required
REDIS_URL:Redis connection URL:required
SECRET_KEY:Django/Flask secret key:auto(64)
ALLOWED_HOSTS:Comma-separated allowed hosts:*
CORS_ORIGINS:CORS allowed origins:*
LOG_LEVEL:Logging level:INFO
WORKER_CONCURRENCY:Number of worker processes:4
API_RATE_LIMIT:API rate limit per minute:100
SENTRY_DSN:Sentry error tracking DSN (optional):'

APP_TEMPLATES["ravynai"]='DATABASE_URL:PostgreSQL connection URL:required
REDIS_URL:Redis connection URL:required
ANTHROPIC_API_KEY:Anthropic Claude API key:required
OPENAI_API_KEY:OpenAI API key (optional):
SECRET_KEY:Application secret key:auto(64)
ALLOWED_HOSTS:Comma-separated allowed hosts:*
LOG_LEVEL:Logging level:INFO
MODEL_NAME:Default Claude model:claude-sonnet-4-20250514
MAX_TOKENS:Maximum response tokens:8192
WORKER_CONCURRENCY:Worker process count:2'

APP_TEMPLATES["frgops"]='DATABASE_URL:PostgreSQL connection URL:required
SESSION_SECRET:Session encryption secret:auto(64)
SMTP_HOST:SMTP mail server:required
SMTP_PORT:SMTP port:587
SMTP_USER:SMTP username:required
SMTP_PASSWORD:SMTP password:required
S3_ENDPOINT:MinIO/S3 endpoint:required
S3_ACCESS_KEY:MinIO/S3 access key:required
S3_SECRET_KEY:MinIO/S3 secret key:required
S3_BUCKET:MinIO/S3 bucket name:frgops
DOMAIN:Application domain:frgops.wheeler.ai
LOG_LEVEL:Logging level:INFO'

APP_TEMPLATES["trading"]='DATABASE_URL:PostgreSQL connection URL:required
NATS_URL:NATS server URL:nats://localhost:4222
TRADING_API_KEY:Exchange API key:required
TRADING_API_SECRET:Exchange API secret:required
REDIS_URL:Redis connection URL:required
LOG_LEVEL:Logging level:INFO
MAX_POSITION_SIZE:Maximum position size:1000
RISK_LIMIT_DAILY:Daily risk limit:50000
PAPER_TRADING:Enable paper trading mode:true
WORKER_COUNT:Trading worker processes:2'

APP_TEMPLATES["ai-agents"]='DATABASE_URL:PostgreSQL connection URL:required
ANTHROPIC_API_KEY:Anthropic Claude API key:required
OPENAI_API_KEY:OpenAI API key (optional):
REDIS_URL:Redis connection URL:required
SECRET_KEY:API authentication secret:auto(64)
AGENT_TIMEOUT:Agent execution timeout seconds:300
MAX_CONCURRENT_AGENTS:Max concurrent agents:10
LOG_LEVEL:Logging level:INFO
AGENT_LOG_DIR:Agent log directory:/opt/wheeler/logs/agents'

APP_TEMPLATES["analytics"]='SUPERSET_SECRET_KEY:Superset encryption key:auto(64)
CLICKHOUSE_PASSWORD:ClickHouse admin password:auto(32)
SUPERSET_ADMIN_USERNAME:Superset admin username:admin
SUPERSET_ADMIN_EMAIL:Superset admin email:admin@wheeler.io
POSTGRES_USER:Analytics Postgres user:superset
POSTGRES_PASSWORD:Analytics Postgres password:auto(32)
POSTGRES_DB:Analytics Postgres database:superset
REDIS_URL:Redis cache URL:required
CLICKHOUSE_HOST:ClickHouse host:localhost'

APP_TEMPLATES["monitoring"]='GRAFANA_ADMIN_PASSWORD:Grafana admin password:auto(32)
GRAFANA_ADMIN_USER:Grafana admin username:admin
GF_SECURITY_SECRET_KEY:Grafana signing key:auto(64)
PROMETHEUS_RETENTION_DAYS:Prometheus data retention:30
ALERTMANAGER_SLACK_WEBHOOK:Slack webhook for alerts (optional):
NETDATA_CLAIM_TOKEN:Netdata cloud token (optional):
NETDATA_CLAIM_ROOMS:Netdata rooms (optional):
UPTIMEKUMA_ADMIN_PASSWORD:Uptime Kuma admin password:auto(32)'

APP_TEMPLATES["postgres"]='POSTGRES_PASSWORD:PostgreSQL superuser password:auto(64)
POSTGRES_USER:PostgreSQL superuser username:postgres
POSTGRES_DB:Default database:aiops
POSTGRES_PORT:PostgreSQL port:5432
POSTGRES_MAX_CONNECTIONS:Maximum connections:200
POSTGRES_SHARED_BUFFERS:Shared buffer memory:2GB
POSTGRES_EFFECTIVE_CACHE:Effective cache size:6GB
PGDATA:Data directory:/var/lib/postgresql/data
BACKUP_SCHEDULE:Backup cron schedule:0 3 * * *
BACKUP_RETENTION_DAYS:Local backup retention:7'

APP_TEMPLATES["redis"]='REDIS_PASSWORD:Redis server password:auto(64)
REDIS_PORT:Redis port:6379
REDIS_MAX_MEMORY:Max memory allocation:4gb
REDIS_EVICTION_POLICY:Eviction policy:allkeys-lru
REDIS_APPEND_ONLY:Enable AOF persistence:yes'

APP_TEMPLATES["messaging"]='NATS_TOKEN:NATS authentication token:auto(64)
NATS_PORT:NATS client port:4222
NATS_HTTP_PORT:NATS monitoring port:8222
NATS_CLUSTER_PORT:NATS cluster port:6222
NATS_MAX_PAYLOAD:Max message size (bytes):1048576
NATS_MAX_CONNECTIONS:Max client connections:1000'

APP_TEMPLATES["traefik"]='CLOUDFLARE_EMAIL:Cloudflare account email:required
CLOUDFLARE_API_KEY:Cloudflare API key (DNS challenge):required
ACME_EMAIL:Let'\''s Encrypt notification email:admin@wheeler.io
TRAEFIK_DASHBOARD_AUTH:Basic auth for dashboard:auto(htpasswd)
LOG_LEVEL:Traefik log level:INFO
ACCESS_LOG:Enable access log:true
METRICS_PROMETHEUS:Enable Prometheus metrics:true
RATE_LIMIT_AVERAGE:Rate limit average req/s:100
RATE_LIMIT_BURST:Rate limit burst:200'

APP_TEMPLATES["n8n"]='N8N_ENCRYPTION_KEY:n8n encryption key:auto(64)
N8N_USER_MANAGEMENT_JWT_SECRET:n8n JWT secret:auto(64)
DB_POSTGRESDB_DATABASE:n8n database name:n8n
DB_POSTGRESDB_USER:n8n database user:n8n
DB_POSTGRESDB_PASSWORD:n8n database password:auto(32)
DB_POSTGRESDB_HOST:PostgreSQL host:localhost
N8N_PORT:n8n webhook port:5678
N8N_PROTOCOL:Protocol:https
N8N_HOST:n8n public host:n8n.wheeler.ai
WEBHOOK_URL:Public webhook URL:https://n8n.wheeler.ai/'

APP_TEMPLATES["management"]='PORTAINER_ADMIN_PASSWORD:Portainer admin password:auto(32)
PORTAINER_EDGE_ID:Portainer Edge ID (optional):
DOCKGE_SECRET_KEY:Dockge secret key:auto(64)'

# --- Generate secure random value -------------------------------------------
generate_secret() {
    local length="${1:-64}"

    # Use /dev/urandom for cryptographic-quality randomness
    # Remove any characters that could cause shell parsing issues
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom 2>/dev/null | head -c "$length" || {
        # Fallback if /dev/urandom not available
        openssl rand -base64 "$((length * 2))" 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c "$length"
    }
}

generate_htpasswd() {
    local username="${1:-admin}"
    local password
    password=$(generate_secret 24)

    # Try to use htpasswd if available
    if command -v htpasswd &>/dev/null; then
        local hashed
        hashed=$(htpasswd -nbB "$username" "$password" 2>/dev/null)
        echo "${hashed}|${password}"
    else
        # Fallback: just return the password (user will need to configure manually)
        echo "${username}:${password}|${password}"
    fi
}

# --- Parse template and generate env file ------------------------------------
generate_env() {
    local app="$1"
    local init_mode="${2:-false}"
    local template="${APP_TEMPLATES[$app]:-}"

    if [[ -z "$template" ]]; then
        # Try to find .env.example in local directory or repo
        if [[ -f ".env.example" ]]; then
            info "Using .env.example as template for ${app}"
            template=$(grep -v '^#' .env.example | grep '=' | sed 's/=.*//' | while read -r var; do
                echo "${var}:From .env.example:required"
            done)
        else
            # Try common repo locations
            for dir in "/opt/wheeler/repos/${app}" "/opt/wheeler/apps/${app}" "${app}"; do
                if [[ -f "${dir}/.env.example" ]]; then
                    info "Found .env.example at ${dir}"
                    template=$(grep -v '^#' "${dir}/.env.example" | grep '=' | sed 's/=.*//' | while read -r var; do
                        echo "${var}:From .env.example:required"
                    done)
                    break
                fi
            done
        fi
    fi

    if [[ -z "$template" ]]; then
        error "No template found for ${app}"
        error "Either add a template to APP_TEMPLATES in this script"
        error "or place a .env.example file in the current directory"
        return 1
    fi

    local env_file="${ENVS_DIR}/${app}.env"
    local env_file_prod="${ENVS_DIR}/${app}.env.production"
    local target_file="${env_file}"

    # Determine if we should use .env or .env.production
    if [[ "$init_mode" == "true" ]]; then
        info "Production mode: will generate ${target_file}"
    fi

    # Check if file already exists
    if [[ -f "$target_file" ]] && [[ "$init_mode" != "force" ]]; then
        warn "Environment file already exists: ${target_file}"
        warn "Use --force to overwrite, or --validate to check it."
        return 0
    fi

    info "Generating environment file for ${app}..."

    # Create envs directory if needed
    mkdir -p "$ENVS_DIR"

    # Build .env content
    local header
    header=$(cat <<HEADER
# ==============================================================================
# ${app}.env — Environment Configuration
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Managed by: env-template.sh
#
# WARNING: This file contains secrets. Handle with care.
# Permissions: chmod 600 (owner read/write only)
# ==============================================================================
#
# To use: docker compose --env-file ${target_file} up -d
#
HEADER
)

    local body=""
    local missing_vars=0

    echo "$template" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local var_name="${line%%:*}"
        local rest="${line#*:}"
        local var_desc="${rest%%:*}"
        local var_default="${rest##*:}"

        local value=""
        local auto_generated=false

        if [[ "$var_default" == "required" ]]; then
            # Check if it already exists in environment
            if [[ -n "${!var_name:-}" ]]; then
                value="${!var_name}"
                info "  ${var_name} <- from environment"
            elif [[ "$init_mode" == "true" ]] || [[ "$init_mode" == "force" ]]; then
                # In init mode, prompt the user
                echo ""
                warn "Required variable: ${var_name} (${var_desc})"
                read -r -p "  Enter value (or press Enter to skip): " user_input
                if [[ -n "$user_input" ]]; then
                    value="$user_input"
                else
                    warn "  SKIPPING ${var_name} — will need manual configuration"
                    missing_vars=$((missing_vars + 1))
                fi
            else
                warn "  ${var_name}: REQUIRED but not set"
                missing_vars=$((missing_vars + 1))
            fi
        elif [[ "$var_default" == auto* ]]; then
            # Auto-generate value
            local length="${var_default#auto(}"
            length="${length%)}"

            if [[ "$length" == "htpasswd" ]]; then
                local generated
                generated=$(generate_htpasswd)
                value="${generated%|*}"
                info "  ${var_name} <- auto-generated (htpasswd)"
            else
                value=$(generate_secret "$length")
                auto_generated=true
            fi
        elif [[ -n "$var_default" ]]; then
            # Use default value
            value="$var_default"
            info "  ${var_name} <- default: ${value}"
        fi

        if [[ -n "$value" ]]; then
            echo "${var_name}=${value}" >> "$target_file.tmp"
            if [[ "$auto_generated" == "true" ]]; then
                auto_generated=false  # Reset for next iteration
            fi
        fi
    done

    # Actually write the file
    echo "$header" > "$target_file"
    echo "" >> "$target_file"

    # Process template variables
    local IFS=$'\n'
    for entry in $template; do
        [[ -z "$entry" ]] && continue

        local var_name="${entry%%:*}"
        local rest="${entry#*:}"
        local var_desc="${rest%%:*}"
        local var_default="${rest##*:}"
        local value=""

        if [[ "$var_default" == "required" ]]; then
            # Check existing env, prompt, or skip
            if [[ -n "${!var_name:-}" ]]; then
                value="${!var_name}"
            elif [[ "$init_mode" == "true" ]] || [[ "$init_mode" == "force" ]]; then
                echo ""
                warn "Required variable: ${var_name} (${var_desc})"
                read -r -p "  Enter value: " user_input
                value="${user_input}"
            fi
        elif [[ "$var_default" == auto* ]]; then
            local length="${var_default#auto(}"
            length="${length%)}"
            if [[ "$length" == "htpasswd" ]]; then
                local generated
                generated=$(generate_htpasswd)
                value="${generated%|*}"
            else
                value=$(generate_secret "$length")
            fi
        elif [[ -n "$var_default" ]]; then
            value="$var_default"
        fi

        if [[ -n "$value" ]]; then
            echo "${var_name}=${value}" >> "$target_file"
            echo "# ${var_name}: ${var_desc} (auto-generated)" >> "$target_file"
        else
            echo "# ${var_name}= # REQUIRED: ${var_desc}" >> "$target_file"
            echo "" >> "$target_file"
        fi
    done

    # Set strict permissions
    chmod 600 "$target_file"
    success "Created: ${target_file} (chmod 600)"

    if [[ $missing_vars -gt 0 ]]; then
        warn "${missing_vars} variable(s) could not be set. Edit ${target_file} manually."
    fi

    # Also create a .env.production symlink or copy
    if [[ "$init_mode" == "true" ]]; then
        cp "$target_file" "${ENVS_DIR}/${app}.env.production" 2>/dev/null || true
        chmod 600 "${ENVS_DIR}/${app}.env.production" 2>/dev/null || true
        success "Also created ${app}.env.production for reference"
    fi

    echo ""
    info "Next steps:"
    info "  1. Review the generated file: cat ${target_file}"
    info "  2. Validate with: $0 ${app} --validate"
    info "  3. Deploy with: deploy-release.sh ${app} main"
}

# --- Validate an existing env file -------------------------------------------
validate_env() {
    local app="$1"
    local env_file="${ENVS_DIR}/${app}.env"

    if [[ ! -f "$env_file" ]]; then
        # Try .env.production
        env_file="${ENVS_DIR}/${app}.env.production"
        if [[ ! -f "$env_file" ]]; then
            error "No environment file found for ${app}"
            error "Looked in:"
            error "  ${ENVS_DIR}/${app}.env"
            error "  ${ENVS_DIR}/${app}.env.production"
            return 1
        fi
    fi

    info "Validating environment file: ${env_file}"

    # Shell-check the file (syntax validation)
    if bash -c "set -a; source '$env_file' 2>/dev/null; set +a" 2>/dev/null; then
        success "Environment file syntax: valid"
    else
        error "Environment file syntax: INVALID"
        error "Check for quoting issues or special characters."
        return 1
    fi

    # Check permissions
    local perms
    perms=$(stat -c '%a' "$env_file" 2>/dev/null || echo "unknown")
    if [[ "$perms" != "600" ]]; then
        warn "Permissions are ${perms} (should be 600). Fix with: chmod 600 ${env_file}"
    else
        success "Permissions: ${perms} (correct)"
    fi

    # Validate against template
    local template="${APP_TEMPLATES[$app]:-}"
    if [[ -n "$template" ]]; then
        local missing=0
        echo "$template" | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local var_name="${line%%:*}"
            local var_default="${line##*:}"

            if [[ "$var_default" == "required" ]]; then
                # Source the file silently and check
                if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
                    local val
                    val=$(grep "^${var_name}=" "$env_file" | head -1 | cut -d= -f2-)
                    if [[ -z "$val" ]]; then
                        warn "  ${var_name}: EMPTY VALUE"
                        missing=$((missing + 1))
                    else
                        info "  ${var_name}: OK (set)"
                    fi
                else
                    warn "  ${var_name}: MISSING"
                    missing=$((missing + 1))
                fi
            fi
        done

        if [[ $missing -gt 0 ]]; then
            error "Validation FAILED — ${missing} required variable(s) missing"
            return 1
        fi
    fi

    success "Environment file validation PASSED"
    return 0
}

# --- Show env file (masked) ---------------------------------------------------
show_env() {
    local app="$1"
    local env_file="${ENVS_DIR}/${app}.env"

    if [[ ! -f "$env_file" ]]; then
        env_file="${ENVS_DIR}/${app}.env.production"
        if [[ ! -f "$env_file" ]]; then
            error "No environment file found for ${app}"
            return 1
        fi
    fi

    echo ""
    echo "=============================================="
    echo "  Environment: ${app}"
    echo "  File: ${env_file}"
    echo "=============================================="
    echo ""

    while IFS= read -r line; do
        # Skip comments and blank lines
        if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
            echo "$line"
            continue
        fi

        # Mask values
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*) ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"

            # Determine if this looks like a secret
            local is_secret=false
            for pattern in "KEY" "SECRET" "PASSWORD" "TOKEN" "AUTH" "SALT" "SIGNATURE" "API_KEY" "ENCRYPTION"; do
                if echo "$var_name" | grep -qi "$pattern"; then
                    is_secret=true
                    break
                fi
            done

            if [[ "$is_secret" == "true" && -n "$var_value" ]]; then
                # Show first 4 characters only
                echo "${var_name}=${var_value:0:4}... (${#var_value} chars)"
            else
                echo "${var_name}=${var_value}"
            fi
        else
            echo "$line"
        fi
    done < "$env_file"

    echo ""
}

# --- List all env files ------------------------------------------------------
list_envs() {
    echo ""
    echo "=============================================="
    echo "  Environment Files"
    echo "  Location: ${ENVS_DIR}"
    echo "=============================================="
    echo ""

    if [[ ! -d "$ENVS_DIR" ]]; then
        warn "Environment directory does not exist: ${ENVS_DIR}"
        return 0
    fi

    local count=0
    for f in "$ENVS_DIR"/*.env*; do
        if [[ -f "$f" ]]; then
            local name
            name=$(basename "$f")
            local size
            size=$(stat -c '%s' "$f" 2>/dev/null || echo "0")
            local perms
            perms=$(stat -c '%a' "$f" 2>/dev/null || echo "unknown")
            local modified
            modified=$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1 || echo "unknown")

            local warning=""
            if [[ "$perms" != "600" ]]; then
                warning=" ${YELLOW}(INSECURE: ${perms})${NC}"
            fi

            echo "  ${name}  (${size} bytes, mode ${perms}) ${warning}"
            echo "    Last modified: ${modified}"
            echo ""

            count=$((count + 1))
        fi
    done

    if [[ $count -eq 0 ]]; then
        info "No environment files found."
        info "Create one with: $0 <app-name> --init"
    else
        success "${count} environment file(s) found"
    fi
}

# --- Main --------------------------------------------------------------------
main() {
    local APP=""
    local ACTION="generate"  # generate, validate, show, list, init

    if [[ $# -eq 0 ]]; then
        list_envs
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --init|--force)
                ACTION="init"
                shift
                ;;
            --validate)
                ACTION="validate"
                shift
                ;;
            --show)
                ACTION="show"
                shift
                ;;
            --list)
                ACTION="list"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [app-name] [options]"
                echo ""
                echo "Options:"
                echo "  --init            Create .env with secure defaults (prompts for required vars)"
                echo "  --force           Overwrite existing .env file"
                echo "  --validate        Validate an existing .env file"
                echo "  --show            Display env vars (secrets masked)"
                echo "  --list            List all environment files"
                echo ""
                echo "Examples:"
                echo "  $0 prediction-radar --init      # Create new env file"
                echo "  $0 ravynai --validate            # Check env file"
                echo "  $0 frgops --show                 # Show masked env"
                echo "  $0 --list                        # List all envs"
                echo ""
                echo "Available apps with templates:"
                for app in "${!APP_TEMPLATES[@]}"; do
                    echo "  - ${app}"
                done | sort
                exit 0
                ;;
            *)
                if [[ -z "$APP" ]]; then
                    APP="$1"
                else
                    error "Unknown argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    case "$ACTION" in
        list)
            list_envs
            ;;
        validate)
            if [[ -z "$APP" ]]; then
                error "Usage: $0 <app-name> --validate"
                exit 1
            fi
            validate_env "$APP"
            ;;
        show)
            if [[ -z "$APP" ]]; then
                error "Usage: $0 <app-name> --show"
                exit 1
            fi
            show_env "$APP"
            ;;
        init|generate|force)
            if [[ -z "$APP" ]]; then
                error "Usage: $0 <app-name> --init"
                exit 1
            fi
            generate_env "$APP" "$ACTION"
            ;;
    esac
}

main "$@"
