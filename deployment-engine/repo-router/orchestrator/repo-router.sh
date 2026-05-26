#!/usr/bin/env bash
# =============================================================================
# Repo Router - Wheeler Deployment Orchestrator
# Source: orchestrator/repo-router.sh
# Description: State-machine pipeline for intake, deploy, rollback, status,
#              drift-check, and dashboard. Implements 14-phase pipeline with
#              non-bypassable gates for Zero-Trust (phase 10) and QA (phase 12).
#
# Usage:
#   ./repo-router.sh intake <repo-url-or-path>   -- Start Phase 01 intake
#   ./repo-router.sh deploy <repo-name>           -- Run full pipeline phases 01-14
#   ./repo-router.sh rollback <repo-name>         -- Rollback to previous version
#   ./repo-router.sh status [repo-name]           -- Show pipeline status
#   ./repo-router.sh drift-check                  -- Run drift detection
#   ./repo-router.sh dashboard                    -- Print summary dashboard
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Source configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROUTER_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROUTER_BASE}/config/repo-router-config.sh" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROUTER_BASE}/config/repo-router-config.sh"
else
  echo "[FATAL] Configuration not found at ${REPO_ROUTER_BASE}/config/repo-router-config.sh"
  echo "Ensure the config file exists and is sourced correctly."
  exit 1
fi

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------
CURRENT_REPO=""
CURRENT_PHASE=0
PHASE_PASSED=true
RUN_ID=""
RUN_STARTED=""
REPO_DIR=""
COMPOSE_FILE=""
NGINX_ROUTE_FILE=""
PM2_FILE=""
PROFILE_FILE="/tmp/repo-profile.json"

TOTAL_PHASES=14

# Phase labels
PHASE_LABELS=(
  "01_intake"
  "02_validate"
  "03_scan"
  "04_profile"
  "05_allocate"
  "06_generate"
  "07_configure"
  "08_build"
  "09_deploy"
  "10_zt_validate"
  "11_health_check"
  "12_qa_gate"
  "13_register"
  "14_finalize"
)

declare -A PHASE_STATUS
for phase in "${PHASE_LABELS[@]}"; do
  PHASE_STATUS["$phase"]="pending"
done

# ---------------------------------------------------------------------------
# Load state file
# ---------------------------------------------------------------------------
load_state() {
  if [[ -f "$REPO_ROUTER_STATE" ]]; then
    if ! jq '.' "$REPO_ROUTER_STATE" &>/dev/null; then
      log_message "WARN" "State file is corrupted. Starting fresh."
      return 1
    fi
    return 0
  else
    log_message "INFO" "No existing state file. Will create on first write."
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Save state to JSON
# ---------------------------------------------------------------------------
save_state() {
  local tmp_state
  tmp_state=$(mktemp)
  local completed_count completed_runs blocked_count blocked_entries repo_profiles

  completed_count=$(jq '.completed_runs.total_completed // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  completed_runs=$(jq '.completed_runs.last_10 // []' "$REPO_ROUTER_STATE" 2>/dev/null || echo "[]")
  blocked_count=$(jq '.blocked_repos.total_blocked // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  blocked_entries=$(jq '.blocked_repos.entries // []' "$REPO_ROUTER_STATE" 2>/dev/null || echo "[]")
  repo_profiles=$(jq '.repo_profiles // {}' "$REPO_ROUTER_STATE" 2>/dev/null || echo "{}")

  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "operational" \
    --arg node "${NODE_TYPE}" \
    --argjson completed_count "$completed_count" \
    --argjson completed_runs "$completed_runs" \
    --argjson blocked_count "$blocked_count" \
    --argjson blocked_entries "$blocked_entries" \
    --argjson repo_profiles "$repo_profiles" \
    '{
      metadata: {
        schema_version: "1.0.0",
        last_updated: $ts,
        description: "Repo Router pipeline state"
      },
      system: {
        status: $status,
        node: $node,
        mode: "active",
        last_drift_check: null,
        last_dashboard_update: $ts,
        last_verification: $ts
      },
      active_runs: {
        total_active: 0,
        runs: []
      },
      completed_runs: {
        total_completed: $completed_count,
        last_10: $completed_runs
      },
      blocked_repos: {
        total_blocked: $blocked_count,
        entries: $blocked_entries
      },
      repo_profiles: $repo_profiles
    }' > "$tmp_state"

  mv "$tmp_state" "$REPO_ROUTER_STATE"
  log_message "INFO" "State saved to ${REPO_ROUTER_STATE}"
}

# ---------------------------------------------------------------------------
# Phase execution wrapper
# ---------------------------------------------------------------------------
run_phase() {
  local phase_num="$1"
  local phase_name="${PHASE_LABELS[$((phase_num - 1))]}"
  local phase_label="${phase_name#*_}"
  local phase_func="phase_${phase_name}"

  CURRENT_PHASE="$phase_num"
  PHASE_PASSED=true
  PHASE_STATUS["$phase_name"]="running"

  log_message "PHASE" "============================================================"
  log_message "PHASE" "Phase ${phase_num}/${TOTAL_PHASES}: ${phase_label}"
  log_message "PHASE" "============================================================"

  # Execute the phase function
  if declare -F "$phase_func" &>/dev/null; then
    if $phase_func; then
      PHASE_STATUS["$phase_name"]="passed"
      log_message "PASS" "Phase ${phase_num} (${phase_label}) completed successfully."
      return 0
    else
      PHASE_PASSED=false
      PHASE_STATUS["$phase_name"]="failed"
      log_message "ERROR" "Phase ${phase_num} (${phase_label}) FAILED."
      return 1
    fi
  else
    log_message "ERROR" "Phase function '$phase_func' not implemented."
    PHASE_PASSED=false
    PHASE_STATUS["$phase_name"]="failed"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Phase 01: Repository Intake
# ---------------------------------------------------------------------------
phase_01_intake() {
  local repo_input="${1:-${CURRENT_REPO}}"

  if [[ -z "$repo_input" ]]; then
    log_message "ERROR" "No repository specified for intake."
    return 1
  fi

  log_message "INFO" "Intaking repository: ${repo_input}"

  # Determine if input is a URL or a local name
  if [[ "$repo_input" =~ ^https?:// ]] || [[ "$repo_input" =~ ^git@ ]]; then
    local repo_name
    repo_name=$(basename "$repo_input" .git)
    REPO_DIR="${DEPLOY_BASE}/${repo_name}"

    if [[ -d "$REPO_DIR" ]]; then
      log_message "INFO" "Repository already cloned at ${REPO_DIR}. Pulling latest..."
      cd "$REPO_DIR"
      git pull --ff-only origin main 2>&1 | log_message "DEBUG" || {
        log_message "WARN" "Git pull failed. Using existing clone."
      }
    else
      log_message "INFO" "Cloning repository from ${repo_input}..."
      mkdir -p "$(dirname "$REPO_DIR")"
      git clone "$repo_input" "$REPO_DIR" 2>&1 | log_message "DEBUG"
      if [[ ! -d "$REPO_DIR" ]]; then
        log_message "ERROR" "Failed to clone repository."
        return 1
      fi
    fi
    CURRENT_REPO="$repo_name"
  elif [[ -d "$repo_input" ]]; then
    REPO_DIR="$repo_input"
    CURRENT_REPO=$(basename "$(cd "$REPO_DIR" && pwd)")
    log_message "INFO" "Using local directory: ${REPO_DIR}"
  else
    # Try to find in registered repos
    if jq -e ".registered_repos | index(\"${repo_input}\")" "$REPO_ROUTER_STATE" &>/dev/null; then
      CURRENT_REPO="$repo_input"
      REPO_DIR="${DEPLOY_BASE}/${CURRENT_REPO}"
      log_message "INFO" "Registered repo found: ${CURRENT_REPO} at ${REPO_DIR}"
    else
      log_message "ERROR" "Repository not found: ${repo_input}. Provide a valid git URL, local path, or registered name."
      return 1
    fi
  fi

  RUN_ID="${CURRENT_REPO}-$(date +%Y%m%d%H%M%S)"
  RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  PROFILE_FILE="/tmp/repo-profile-${RUN_ID}.json"
  log_message "INFO" "Run ID: ${RUN_ID}"
  log_message "INFO" "Repo path: ${REPO_DIR}"

  # Detect repo type
  if [[ -f "${REPO_DIR}/docker-compose.yml" ]] || [[ -f "${REPO_DIR}/Dockerfile" ]]; then
    log_message "INFO" "Detected Docker-based project."
  elif [[ -f "${REPO_DIR}/ecosystem.config.js" ]] || [[ -f "${REPO_DIR}/package.json" ]]; then
    log_message "INFO" "Detected Node.js/PM2 project."
  elif [[ -f "${REPO_DIR}/requirements.txt" ]] || [[ -f "${REPO_DIR}/pyproject.toml" ]]; then
    log_message "INFO" "Detected Python project."
  else
    log_message "WARN" "Could not determine project type from repo structure."
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Phase 02: Validation
# ---------------------------------------------------------------------------
phase_02_validate() {
  log_message "INFO" "Validating repository structure..."

  local required_files=()
  local optional_files=()

  if [[ -f "${REPO_DIR}/docker-compose.yml" ]]; then
    required_files+=("docker-compose.yml")
  fi
  if [[ -f "${REPO_DIR}/Dockerfile" ]]; then
    required_files+=("Dockerfile")
  fi
  if [[ -f "${REPO_DIR}/package.json" ]]; then
    required_files+=("package.json")
  fi
  if [[ -f "${REPO_DIR}/requirements.txt" ]]; then
    optional_files+=("requirements.txt")
  fi

  local all_valid=true
  for f in "${required_files[@]}"; do
    if [[ -f "${REPO_DIR}/${f}" ]]; then
      log_message "INFO" "  [OK] ${f} found"
    else
      log_message "WARN" "  [MISSING] ${f} not found"
      all_valid=false
    fi
  done

  # Check for .git
  if [[ -d "${REPO_DIR}/.git" ]]; then
    log_message "INFO" "  [OK] Git repository"
  else
    log_message "WARN" "  [MISSING] Not a git repository"
  fi

  # Validate docker-compose if present
  if [[ -f "${REPO_DIR}/docker-compose.yml" ]] && command -v docker-compose &>/dev/null; then
    if docker-compose -f "${REPO_DIR}/docker-compose.yml" config -q 2>/dev/null; then
      log_message "INFO" "  [OK] docker-compose.yml is valid"
    else
      log_message "ERROR" "  [INVALID] docker-compose.yml has syntax errors"
      all_valid=false
    fi
  fi

  if [[ "$all_valid" == "false" ]]; then
    log_message "WARN" "Validation completed with warnings (not blocking)."
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Phase 03: Security Scan (NON-BYPASSABLE)
# ---------------------------------------------------------------------------
phase_03_scan() {
  log_message "INFO" "Running security scans..."

  local scan_failed=false

  # Check for secrets in files
  log_message "INFO" "Scanning for hardcoded secrets..."
  local secret_patterns=("DEEPSEEK_API_KEY" "ANTHROPIC_API_KEY" "OPENAI_API_KEY"
                         "SK-" "ghp_" "gho_" "ghs_" "ghb_" "github_pat"
                         "-----BEGIN RSA PRIVATE KEY-----"
                         "-----BEGIN OPENSSH PRIVATE KEY-----"
                         "-----BEGIN EC PRIVATE KEY-----"
                         "password" "PASSWORD" "SECRET_KEY" "API_KEY")

  for pattern in "${secret_patterns[@]}"; do
    if grep -rl "$pattern" "${REPO_DIR}/" --include="*.{py,js,ts,jsx,tsx,yml,yaml,json,env,txt,sh,conf,cfg}" 2>/dev/null \
      | grep -v node_modules | grep -v .git | grep -v .env | head -3 | grep -q .; then
      log_message "WARN" "  Potential secret pattern found: ${pattern}"
      scan_failed=true
    fi
  done

  # Check permissions
  log_message "INFO" "Checking file permissions..."
  local dangerous_perms=false
  while IFS= read -r -d '' file; do
    if [[ -f "$file" ]] && [[ "$(stat -c '%a' "$file")" =~ ^777|755|666 ]]; then
      if [[ "$file" == *.sh ]] || [[ "$file" == *.py ]]; then
        continue  # Executable scripts are fine
      fi
      log_message "WARN" "  World-readable/writable: ${file#${REPO_DIR}/}"
      dangerous_perms=true
    fi
  done < <(find "${REPO_DIR}" -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/__pycache__/*' -type f -print0 2>/dev/null)

  if [[ -f "${REPO_DIR}/Dockerfile" ]]; then
    log_message "INFO" "Checking Dockerfile for security issues..."
    if grep -q "EXPOSE 0.0.0.0" "${REPO_DIR}/Dockerfile" 2>/dev/null; then
      log_message "WARN" "  Dockerfile exposes 0.0.0.0 - should bind to 127.0.0.1"
    fi
  fi

  if [[ "$scan_failed" == "true" ]]; then
    log_message "ERROR" "Security scan found issues that must be resolved before deployment."
    log_message "WARN" "This is a non-bypassable gate. Fix the issues and re-run."
    return 1
  fi

  log_message "INFO" "Security scan passed. No critical issues found."
  return 0
}

# ---------------------------------------------------------------------------
# Phase 04: Profiling
# ---------------------------------------------------------------------------
phase_04_profile() {
  log_message "INFO" "Generating repository profile..."

  local language="unknown"
  local framework="unknown"
  local repo_type="backend"

  # Detect language and repo type
  if [[ -f "${REPO_DIR}/package.json" ]]; then
    language="typescript"
    # CLI detection: packages with bin field
    if jq -e '.bin' "${REPO_DIR}/package.json" &>/dev/null; then
      framework="node-cli"
      repo_type="cli"
    elif jq -e '.dependencies.next' "${REPO_DIR}/package.json" &>/dev/null; then
      framework="nextjs"
      repo_type="fullstack"
    elif jq -e '.dependencies.react' "${REPO_DIR}/package.json" &>/dev/null; then
      framework="react"
      repo_type="frontend"
    elif jq -e '.dependencies.express' "${REPO_DIR}/package.json" &>/dev/null; then
      framework="express"
      repo_type="backend"
    elif jq -e '.dependencies.vue' "${REPO_DIR}/package.json" &>/dev/null; then
      framework="vue"
      repo_type="frontend"
    else
      framework="node"
      repo_type="backend"
    fi
  elif [[ -f "${REPO_DIR}/requirements.txt" ]] || [[ -f "${REPO_DIR}/pyproject.toml" ]]; then
    language="python"
    if grep -qi "fastapi" "${REPO_DIR}/requirements.txt" 2>/dev/null; then
      framework="fastapi"
      repo_type="backend"
    elif grep -qi "django" "${REPO_DIR}/requirements.txt" 2>/dev/null; then
      framework="django"
      repo_type="backend"
    elif grep -qi "flask" "${REPO_DIR}/requirements.txt" 2>/dev/null; then
      framework="flask"
      repo_type="backend"
    elif grep -qi "matplotlib\|numpy\|pandas\|scipy\|jupyter\|pillow\|PIL\|opencv" "${REPO_DIR}/requirements.txt" 2>/dev/null; then
      framework="python-data"
      repo_type="library"
    else
      framework="python"
      repo_type="backend"
    fi
  elif [[ -f "${REPO_DIR}/go.mod" ]]; then
    language="go"
    framework="go"
    repo_type="cli"
  elif [[ -f "${REPO_DIR}/Cargo.toml" ]]; then
    language="rust"
    framework="rust"
    repo_type="cli"
  elif [[ -f "${REPO_DIR}/Makefile" ]] && grep -q "install\|build" "${REPO_DIR}/Makefile" 2>/dev/null; then
    language="c"
    framework="make"
    repo_type="cli"
  fi

  # Detect agent type (GPU requirements)
  if [[ -f "${REPO_DIR}/Dockerfile" ]] && grep -qi "nvidia\|cuda\|gpu" "${REPO_DIR}/Dockerfile" 2>/dev/null; then
    repo_type="agent"
  fi

  # Detect static site
  if [[ -f "${REPO_DIR}/index.html" ]] && [[ ! -f "${REPO_DIR}/package.json" ]]; then
    repo_type="static"
    framework="html"
  fi

  # Detect shell script repos (no package manager, has .sh files)
  if [[ "$language" == "unknown" ]]; then
    local sh_count
    sh_count=$(find "${REPO_DIR}" -maxdepth 2 -name "*.sh" -not -path '*/.git/*' 2>/dev/null | wc -l)
    if [[ "$sh_count" -gt 3 ]]; then
      language="shell"
      framework="bash"
      repo_type="cli"
    fi
  fi

  # Detect static/data repos (no build system, mostly data/config files)
  if [[ "$language" == "unknown" ]]; then
    local data_extensions="txt md json yaml yml csv xml toml conf ini cfg"
    local code_extensions="py js ts go rs c cpp h java rb php"
    local data_count=0 code_count=0
    while IFS= read -r -d '' f; do
      local ext="${f##*.}"
      if echo "$data_extensions" | grep -qw "$ext"; then data_count=$((data_count + 1)); fi
      if echo "$code_extensions" | grep -qw "$ext"; then code_count=$((code_count + 1)); fi
    done < <(find "${REPO_DIR}" -maxdepth 3 -type f -not -path '*/.git/*' -print0 2>/dev/null)
    if [[ "$data_count" -gt "$code_count" ]] && [[ "$code_count" -lt 3 ]]; then
      language="data"
      framework="static"
      repo_type="static"
    fi
  fi

  log_message "INFO" "  Language: ${language}"
  log_message "INFO" "  Framework: ${framework}"
  log_message "INFO" "  Type: ${repo_type}"

  # Store profile for later phases
  cat > "${PROFILE_FILE}" <<PROFILEEOF
{
  "name": "${CURRENT_REPO}",
  "repo_type": "${repo_type}",
  "language": "${language}",
  "framework": "${framework}",
  "node": "${NODE_TYPE}",
  "port": 0,
  "status": "profiled",
  "current_phase": 4
}
PROFILEEOF

  return 0
}

# ---------------------------------------------------------------------------
# Phase 05: Port Allocation (NON-BYPASSABLE)
# ---------------------------------------------------------------------------
phase_05_allocate() {
  log_message "INFO" "Allocating ports from port-allocation-table..."

  if ! load_json "$PORT_ALLOCATION_TABLE"; then
    log_message "ERROR" "Cannot validate port allocation without port-allocation-table.json"
    return 1
  fi

  local repo_name="$CURRENT_REPO"
  local allocated_port
  allocated_port=$(jq -r ".services.\"${repo_name}\".port // .services.\"${repo_name}-api\".port // 0" "$PORT_ALLOCATION_TABLE")

  if [[ "$allocated_port" == "0" ]] || [[ "$allocated_port" == "null" ]]; then
    log_message "WARN" "No static port allocation found for '${repo_name}' in port-allocation-table."

    # Auto-allocate from dynamic pool (5000-5999)
    local found_port=0
    for port in $(seq 5000 5999 | shuf); do
      if check_port_available "$port"; then
        found_port=$port
        break
      fi
    done

    if [[ "$found_port" -eq 0 ]]; then
      log_message "ERROR" "No available ports in dynamic pool (5000-5999)."
      return 1
    fi

    allocated_port=$found_port
    log_message "WARN" "  Auto-allocated port ${allocated_port} (not in static table). Update port-allocation-table.json."
  else
    local bind_addr
    bind_addr=$(jq -r ".services.\"${repo_name}\".bind_address // .services.\"${repo_name}-api\".bind_address // \"127.0.0.1\"" "$PORT_ALLOCATION_TABLE")

    # Check for port conflicts
    if ! check_port_available "$allocated_port"; then
      log_message "ERROR" "Port ${allocated_port} is already in use on ${bind_addr}!"
      log_message "ERROR" "This is a non-bypassable gate. Resolve the port conflict and re-run."
      return 1
    fi

    log_message "INFO" "  Allocated port: ${allocated_port} (bind: ${bind_addr})"
  fi

  # Update profile with port
  jq --argjson port "$allocated_port" '.port = $port | .current_phase = 5' "${PROFILE_FILE}" > "${PROFILE_FILE}.tmp"
  mv "${PROFILE_FILE}.tmp" "${PROFILE_FILE}"

  return 0
}

# ---------------------------------------------------------------------------
# Phase 06: Template Generation
# ---------------------------------------------------------------------------
phase_06_generate() {
  log_message "INFO" "Generating deployment templates..."

  local repo_type
  repo_type=$(jq -r '.repo_type' "${PROFILE_FILE}")

  # cli, library, and static repos don't need Docker/nginx/PM2
  if [[ "$repo_type" == "cli" ]] || [[ "$repo_type" == "library" ]] || [[ "$repo_type" == "static" ]]; then
    log_message "INFO" "  Repo type '${repo_type}' does not require Docker/nginx/PM2 generation."
    log_message "INFO" "  Skipping compose, nginx route, and PM2 config generation."
    COMPOSE_FILE=""
    NGINX_ROUTE_FILE=""
    PM2_FILE=""
    return 0
  fi

  # Even for backend/frontend/etc, skip Docker if no real Dockerfile exists
  if [[ ! -f "${REPO_DIR}/Dockerfile" ]] && [[ ! -f "${REPO_DIR}/docker-compose.yml" ]]; then
    log_message "INFO" "  No Dockerfile or docker-compose.yml found — skipping Docker generation."
    log_message "INFO" "  Repo will be available as native build at: ${REPO_DIR}"
    COMPOSE_FILE=""
    NGINX_ROUTE_FILE=""
    PM2_FILE=""
    return 0
  fi

  # Select compose template based on repo type
  local compose_template=""
  case "$repo_type" in
    "frontend") compose_template="${REPO_ROUTER_TEMPLATES}/docker/compose.static.yml" ;;
    "fullstack") compose_template="${REPO_ROUTER_TEMPLATES}/docker/compose.fullstack.yml" ;;
    "agent") compose_template="${REPO_ROUTER_TEMPLATES}/docker/compose.agent.yml" ;;
    "backend")
      local lang
      lang=$(jq -r '.language' "${PROFILE_FILE}")
      if [[ "$lang" == "python" ]]; then
        compose_template="${REPO_ROUTER_TEMPLATES}/docker/compose.python.yml"
      else
        compose_template="${REPO_ROUTER_TEMPLATES}/docker/compose.nodejs.yml"
      fi
      ;;
    "static") compose_template="${REPO_ROUTER_TEMPLATES}/docker/compose.static.yml" ;;
    *) compose_template="${REPO_ROUTER_TEMPLATES}/docker/compose.nodejs.yml" ;;
  esac

  # Generate compose file
  COMPOSE_FILE="${REPO_DIR}/docker-compose.generated.yml"
  if [[ -f "$compose_template" ]]; then
    cp "$compose_template" "$COMPOSE_FILE"
    log_message "INFO" "  Generated compose: ${COMPOSE_FILE} from ${compose_template}"
  else
    log_message "WARN" "  No compose template found for type '${repo_type}'. Skipping compose generation."
  fi

  # Generate nginx route if applicable
  local node_type
  node_type=$(jq -r '.node' "${PROFILE_FILE}")
  NGINX_ROUTE_FILE="${REPO_DIR}/nginx-route.conf"

  local nginx_template=""
  case "$node_type" in
    "aiops") nginx_template="${REPO_ROUTER_TEMPLATES}/nginx/route-aiops.conf" ;;
    "hostinger") nginx_template="${REPO_ROUTER_TEMPLATES}/nginx/route-hostinger.conf" ;;
    "coredb") nginx_template="${REPO_ROUTER_TEMPLATES}/nginx/route-tailscale.conf" ;;
  esac

  if [[ -f "$nginx_template" ]]; then
    cp "$nginx_template" "$NGINX_ROUTE_FILE"
    log_message "INFO" "  Generated nginx route: ${NGINX_ROUTE_FILE}"
  else
    log_message "INFO" "  No nginx template needed for node type '${node_type}'."
  fi

  # Generate PM2 config if Node.js
  local lang
  lang=$(jq -r '.language' "${PROFILE_FILE}")
  if [[ "$lang" == "typescript" ]] || [[ "$lang" == "javascript" ]]; then
    PM2_FILE="${REPO_DIR}/${DEPLOY_PM2_CONFIG}"
    if [[ -f "${REPO_ROUTER_TEMPLATES}/pm2/ecosystem.config.js" ]] && [[ ! -f "$PM2_FILE" ]]; then
      cp "${REPO_ROUTER_TEMPLATES}/pm2/ecosystem.config.js" "$PM2_FILE"
      log_message "INFO" "  Generated PM2 config: ${PM2_FILE}"
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Phase 07: Configuration
# ---------------------------------------------------------------------------
phase_07_configure() {
  log_message "INFO" "Applying runtime configuration..."

  local port
  port=$(jq -r '.port' "${PROFILE_FILE}")

  # Create .env if it doesn't exist
  if [[ ! -f "${REPO_DIR}/.env" ]]; then
    cat > "${REPO_DIR}/.env" <<ENVEOF
# Generated by Repo Router - Phase 07 Configuration
NODE_ENV=production
PORT=${port}
LOG_LEVEL=info
BIND_ADDRESS=127.0.0.1
ENVEOF
    log_message "INFO" "  Created .env file with PORT=${port}"
  else
    log_message "INFO" "  .env file already exists, not overwriting"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Phase 08: Build
# ---------------------------------------------------------------------------
phase_08_build() {
  log_message "INFO" "Building deployment artifacts..."

  local repo_type
  local language
  repo_type=$(jq -r '.repo_type' "${PROFILE_FILE}")
  language=$(jq -r '.language' "${PROFILE_FILE}")

  # Non-service repos should never try Docker, regardless of stale files on disk
  if [[ "$repo_type" == "cli" ]] || [[ "$repo_type" == "library" ]] || [[ "$repo_type" == "static" ]]; then
    log_message "INFO" "  Repo type '${repo_type}' — checking for native build system..."
    # Fall through to native build below
  fi

  local has_dockerfile=false
  local has_real_dockerfile=false
  if [[ "$repo_type" != "cli" && "$repo_type" != "library" && "$repo_type" != "static" ]]; then
    [[ -f "${REPO_DIR}/Dockerfile" ]] && has_dockerfile=true && has_real_dockerfile=true
    [[ -f "${REPO_DIR}/docker-compose.yml" ]] && has_dockerfile=true && has_real_dockerfile=true
    [[ -f "${REPO_DIR}/docker-compose.generated.yml" ]] && has_dockerfile=true
  fi

  # Docker build (only when real Dockerfile/compose exists, not just generated)
  if [[ "$has_real_dockerfile" == "true" ]]; then
    log_message "INFO" "  Building Docker images..."
    local compose_file="${REPO_DIR}/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
      compose_file="${REPO_DIR}/docker-compose.generated.yml"
    fi
    if [[ -f "$compose_file" ]]; then
      cd "${REPO_DIR}"
      if docker-compose -f "$compose_file" build 2>&1 | tail -5; then
        log_message "INFO" "  Docker build completed."
      else
        log_message "ERROR" "  Docker build failed."
        return 1
      fi
    elif [[ -f "${REPO_DIR}/Dockerfile" ]]; then
      cd "${REPO_DIR}"
      if docker build -t "${CURRENT_REPO}:latest" . 2>&1 | tail -5; then
        log_message "INFO" "  Docker build completed."
      else
        log_message "ERROR" "  Docker build failed."
        return 1
      fi
    fi

  # Go build
  elif [[ "$language" == "go" ]] && [[ -f "${REPO_DIR}/go.mod" ]]; then
    log_message "INFO" "  Building Go project..."
    cd "${REPO_DIR}"
    if go build ./... 2>&1 | tail -5; then
      log_message "INFO" "  Go build completed."
    elif go build -o "${CURRENT_REPO}" . 2>&1 | tail -5; then
      log_message "INFO" "  Go build (single binary) completed."
    else
      log_message "WARN" "  Go build had issues (non-blocking for CLI)."
    fi

  # Rust/Cargo build
  elif [[ "$language" == "rust" ]] && [[ -f "${REPO_DIR}/Cargo.toml" ]]; then
    log_message "INFO" "  Building Rust project..."
    cd "${REPO_DIR}"
    if cargo build --release 2>&1 | tail -5; then
      log_message "INFO" "  Cargo build completed."
    else
      log_message "WARN" "  Cargo build had issues (non-blocking for CLI)."
    fi

  # Node.js build (npm/pnpm)
  elif [[ -f "${REPO_DIR}/package.json" ]]; then
    log_message "INFO" "  Installing Node.js dependencies..."
    cd "${REPO_DIR}"
    local pkg_mgr="npm"
    if [[ -f "${REPO_DIR}/pnpm-lock.yaml" ]]; then pkg_mgr="pnpm"; fi

    if [[ "$pkg_mgr" == "pnpm" ]]; then
      if pnpm install --prod 2>&1 | tail -3; then
        log_message "INFO" "  pnpm install completed."
      elif pnpm install 2>&1 | tail -3; then
        log_message "INFO" "  pnpm install (full) completed."
      else
        log_message "WARN" "  pnpm install had issues (non-blocking)."
      fi
    elif npm ci --production 2>&1 | tail -3; then
      log_message "INFO" "  npm ci completed."
    elif npm install --production 2>&1 | tail -3; then
      log_message "INFO" "  npm install completed."
    else
      log_message "WARN" "  npm install had issues (non-blocking)."
    fi

    if [[ -f "${REPO_DIR}/tsconfig.json" ]]; then
      log_message "INFO" "  Building TypeScript..."
      npx tsc --noEmit 2>&1 | tail -5 || log_message "WARN" "  TypeScript build had issues (non-blocking)."
    fi

  # Python install
  elif [[ -f "${REPO_DIR}/requirements.txt" ]]; then
    log_message "INFO" "  Installing Python dependencies..."
    cd "${REPO_DIR}"
    if pip install -r requirements.txt --quiet 2>&1 | tail -3; then
      log_message "INFO" "  pip install completed."
    else
      log_message "WARN" "  pip install had issues (non-blocking for library)."
    fi

  # Makefile build
  elif [[ -f "${REPO_DIR}/Makefile" ]]; then
    log_message "INFO" "  Running make..."
    cd "${REPO_DIR}"
    if make 2>&1 | tail -5; then
      log_message "INFO" "  make completed."
    else
      log_message "WARN" "  make had issues (non-blocking)."
    fi

  else
    log_message "INFO" "  No build system detected. Repo type '${repo_type}' requires no build."
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Phase 09: Deploy
# ---------------------------------------------------------------------------
phase_09_deploy() {
  log_message "INFO" "Deploying service..."

  local repo_type
  repo_type=$(jq -r '.repo_type' "${PROFILE_FILE}")

  # cli, library, and static repos are not long-running services
  if [[ "$repo_type" == "cli" ]] || [[ "$repo_type" == "library" ]] || [[ "$repo_type" == "static" ]]; then
    log_message "INFO" "  Repo type '${repo_type}' is not a service — skipping Docker/PM2/nginx deploy."
    log_message "INFO" "  Repo is available at: ${REPO_DIR}"
    return 0
  fi

  # Docker deployment
  if [[ -f "${REPO_DIR}/docker-compose.generated.yml" ]]; then
    log_message "INFO" "  Starting Docker containers..."
    cd "${REPO_DIR}"
    if docker-compose -f docker-compose.generated.yml up -d 2>&1 | tail -5; then
      log_message "INFO" "  Docker containers started."
    else
      log_message "ERROR" "  Failed to start Docker containers."
      return 1
    fi
  elif [[ -f "${REPO_DIR}/docker-compose.yml" ]]; then
    log_message "INFO" "  Starting Docker containers (existing compose)..."
    cd "${REPO_DIR}"
    if docker-compose up -d 2>&1 | tail -5; then
      log_message "INFO" "  Docker containers started."
    else
      log_message "ERROR" "  Failed to start Docker containers."
      return 1
    fi
  fi

  # PM2 deployment (only if ecosystem.config.js AND it's a service type)
  if [[ -f "${REPO_DIR}/package.json" ]] && [[ -f "${REPO_DIR}/ecosystem.config.js" ]]; then
    log_message "INFO" "  Starting PM2 process..."
    cd "${REPO_DIR}"

    if [[ -f "${REPO_ROUTER_TEMPLATES}/pm2/env-wrapper.sh" ]]; then
      local env_file="${REPO_DIR}/.env"
      if [[ -f "$env_file" ]]; then
        bash "${REPO_ROUTER_TEMPLATES}/pm2/env-wrapper.sh" "${CURRENT_REPO}" "$env_file" -- \
          start ecosystem.config.js --env production 2>&1 | tail -5 || true
      fi
    fi

    if pm2 start ecosystem.config.js --env production 2>&1 | tail -5; then
      pm2 save
      log_message "INFO" "  PM2 process started and saved."
    else
      log_message "WARN" "  PM2 start attempt completed (check status)."
    fi
  fi

  # Activate nginx route (only if generated AND service is running)
  if [[ -f "${REPO_DIR}/nginx-route.conf" ]]; then
    log_message "INFO" "  Activating nginx route..."
    if [[ -d "$DEPLOY_NGINX_AVAILABLE" ]]; then
      cp "${REPO_DIR}/nginx-route.conf" "${DEPLOY_NGINX_AVAILABLE}/${CURRENT_REPO}.conf"
      ln -sf "${DEPLOY_NGINX_AVAILABLE}/${CURRENT_REPO}.conf" "${DEPLOY_NGINX_ENABLED}/${CURRENT_REPO}.conf"
      if nginx -t 2>&1 | tail -1; then
        nginx -s reload 2>/dev/null || systemctl reload nginx 2>/dev/null || true
        log_message "INFO" "  Nginx route activated and reloaded."
      else
        log_message "WARN" "  Nginx config test failed. Route not activated."
      fi
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Phase 10: Zero-Trust Validation (NON-BYPASSABLE)
# ---------------------------------------------------------------------------
phase_10_zt_validate() {
  log_message "INFO" "=== NON-BYPASSABLE GATE: Zero-Trust Validation ==="

  local port
  port=$(jq -r '.port' "${PROFILE_FILE}")
  local repo_type
  repo_type=$(jq -r '.repo_type' "${PROFILE_FILE}")
  local zt_failed=false

  # For cli/library/static repos: validate repo integrity only
  if [[ "$repo_type" == "cli" ]] || [[ "$repo_type" == "library" ]] || [[ "$repo_type" == "static" ]]; then
    log_message "INFO" "  Repo type '${repo_type}' — running simplified ZT checks (repo integrity)."

    if [[ ! -d "${REPO_DIR}/.git" ]]; then
      log_message "ERROR" "  FAIL: Not a git repository."
      zt_failed=true
    else
      log_message "PASS" "  Git repository integrity verified."
    fi

    if [[ -f "${REPO_DIR}/.env" ]]; then
      if grep -q "DEEPSEEK_API_KEY\|ANTHROPIC_API_KEY\|OPENAI_API_KEY" "${REPO_DIR}/.env" 2>/dev/null; then
        log_message "ERROR" "  FAIL: API keys found in .env file!"
        zt_failed=true
      else
        log_message "PASS" "  No API keys in .env."
      fi
    fi

    if [[ "$zt_failed" == "true" ]]; then
      log_message "ERROR" "Zero-Trust Validation FAILED for ${repo_type} repo."
      return 1
    fi

    log_message "PASS" "Zero-Trust Validation passed for ${repo_type} repo."
    return 0
  fi

  log_message "INFO" "Checking bind address for port ${port}..."
  if ss -tlnp "sport = :${port}" 2>/dev/null | grep -qP "0\.0\.0\.0:${port}\s"; then
    log_message "ERROR" "  FAIL: Service on port ${port} is bound to 0.0.0.0 (all interfaces)!"
    log_message "ERROR" "  All services must bind to 127.0.0.1 per Wheeler security policy."
    zt_failed=true
  elif ss -tlnp "sport = :${port}" 2>/dev/null | grep -qP "127\.0\.0\.1:${port}\s"; then
    log_message "PASS" "  Service on port ${port} correctly bound to 127.0.0.1."
  else
    log_message "WARN" "  Port ${port} not yet listening (may still be starting). Will verify on health check."
  fi

  # Check that no containers expose ports to 0.0.0.0
  log_message "INFO" "Checking Docker containers for exposed ports..."
  if command -v docker &>/dev/null; then
    local exposed_containers
    exposed_containers=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -v "127.0.0.1" | grep -P "0\.0\.0\.0:\d+" || true)
    if [[ -n "$exposed_containers" ]]; then
      log_message "WARN" "  Containers exposed to 0.0.0.0:"
      echo "$exposed_containers" | while IFS= read -r line; do
        log_message "WARN" "    ${line}"
      done
      zt_failed=true
    fi
  fi

  # Verify no privileged containers
  log_message "INFO" "Checking for privileged containers..."
  if command -v docker &>/dev/null; then
    local priv_containers
    priv_containers=$(docker ps --filter "name=${CURRENT_REPO}" --format '{{.Names}}' 2>/dev/null | xargs -I{} sh -c 'docker inspect {} --format "{{.Name}} {{.HostConfig.Privileged}}"' 2>/dev/null | grep " true" || true)
    if [[ -n "$priv_containers" ]]; then
      log_message "ERROR" "  Privileged containers found: ${priv_containers}"
      zt_failed=true
    fi
  fi

  if [[ "$zt_failed" == "true" ]]; then
    log_message "ERROR" "Zero-Trust Validation FAILED. This is a NON-BYPASSABLE gate."
    log_message "ERROR" "Fix the security issues and re-run the pipeline."
    return 1
  fi

  log_message "PASS" "Zero-Trust Validation passed. All services properly secured."
  return 0
}

# ---------------------------------------------------------------------------
# Phase 11: Health Check
# ---------------------------------------------------------------------------
phase_11_health_check() {
  log_message "INFO" "Running health checks..."

  local port
  port=$(jq -r '.port' "${PROFILE_FILE}")
  local repo_type
  repo_type=$(jq -r '.repo_type' "${PROFILE_FILE}")
  local health_endpoint="/health"

  # For cli/library/static repos: verify repo health (git + file integrity)
  if [[ "$repo_type" == "cli" ]] || [[ "$repo_type" == "library" ]] || [[ "$repo_type" == "static" ]]; then
    log_message "INFO" "  Repo type '${repo_type}' — checking repo health (git integrity + symlinks)."
    local checks_passed=0
    local checks_failed=0

    cd "${REPO_DIR}"
    if git status &>/dev/null; then
      log_message "PASS" "  Git repository is healthy."
      checks_passed=$((checks_passed + 1))
    else
      log_message "WARN" "  Git repository has issues."
      checks_failed=$((checks_failed + 1))
    fi

    local broken_links
    broken_links=$(find "${REPO_DIR}" -xtype l 2>/dev/null | wc -l)
    if [[ "$broken_links" -eq 0 ]]; then
      log_message "PASS" "  No broken symlinks."
      checks_passed=$((checks_passed + 1))
    else
      log_message "WARN" "  ${broken_links} broken symlink(s) found."
      checks_failed=$((checks_failed + 1))
    fi

    if [[ "$checks_failed" -gt 0 ]]; then
      log_message "WARN" "Health check completed with ${checks_failed} warning(s)."
    else
      log_message "PASS" "Health check passed (${checks_passed}/$((checks_passed + checks_failed)))."
    fi
    return 0
  fi

  # Get health endpoint from profile if set
  if jq -e '.health_endpoint' "${PROFILE_FILE}" &>/dev/null; then
    health_endpoint=$(jq -r '.health_endpoint.endpoint // "/health"' "${PROFILE_FILE}")
  fi

  local health_url="http://127.0.0.1:${port}${health_endpoint}"
  local checks_passed=0
  local checks_failed=0

  log_message "INFO" "  Checking: ${health_url}"

  for ((i = 1; i <= HEALTH_CHECK_RETRIES; i++)); do
    if curl --fail --silent --output /dev/null --max-time "${HEALTH_CHECK_TIMEOUT}" "$health_url" 2>/dev/null; then
      log_message "PASS" "  Health check passed (attempt ${i}/${HEALTH_CHECK_RETRIES})"
      checks_passed=$((checks_passed + 1))
      break
    else
      if [[ $i -lt $HEALTH_CHECK_RETRIES ]]; then
        log_message "WARN" "  Health check attempt ${i}/${HEALTH_CHECK_RETRIES} failed. Retrying in ${HEALTH_CHECK_INTERVAL}s..."
        sleep "${HEALTH_CHECK_INTERVAL}"
      else
        log_message "WARN" "  Health check failed after ${HEALTH_CHECK_RETRIES} attempts (endpoint may not expose /health)."
        checks_failed=$((checks_failed + 1))
      fi
    fi
  done

  # Check PM2 process health if applicable
  if command -v pm2 &>/dev/null && pm2 list 2>/dev/null | grep -q "$CURRENT_REPO"; then
    local pm2_status
    pm2_status=$(pm2 show "$CURRENT_REPO" 2>/dev/null | grep "status" | awk '{print $NF}' || echo "unknown")
    if [[ "$pm2_status" == "online" ]]; then
      log_message "PASS" "  PM2 process status: ${pm2_status}"
    else
      log_message "WARN" "  PM2 process status: ${pm2_status} (expected: online)"
      checks_failed=$((checks_failed + 1))
    fi
  fi

  if [[ "$checks_failed" -gt 0 ]]; then
    log_message "WARN" "Health check completed with ${checks_failed} failure(s)."
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Phase 12: QA Gate (NON-BYPASSABLE)
# ---------------------------------------------------------------------------
phase_12_qa_gate() {
  log_message "INFO" "=== NON-BYPASSABLE GATE: QA Scorecard ==="

  local repo_type
  repo_type=$(jq -r '.repo_type' "${PROFILE_FILE}")
  local score=100
  local deductions=()

  # For cli/library/static repos: simplified QA scoring
  if [[ "$repo_type" == "cli" ]] || [[ "$repo_type" == "library" ]] || [[ "$repo_type" == "static" ]]; then
    log_message "INFO" "  Repo type '${repo_type}' — simplified QA scoring (threshold: 60)."

    # 1. Repo cloned and accessible (40 points)
    if [[ -d "$REPO_DIR" ]] && [[ -d "${REPO_DIR}/.git" ]]; then
      log_message "PASS" "  [1/3] Repo cloned with git history."
    else
      deductions+=("-40: Repo not properly cloned")
    fi

    # 2. No secrets in repo (30 points)
    log_message "INFO" "  [2/3] Checking for secrets..."
    if grep -rq "DEEPSEEK_API_KEY\|ANTHROPIC_API_KEY\|OPENAI_API_KEY" "${REPO_DIR}/" --include="*.{env,txt,sh,py,js,ts,yml,yaml}" 2>/dev/null; then
      deductions+=("-30: API keys found in repo files")
    else
      log_message "PASS" "  No secrets detected."
    fi

    # 3. README or docs present (30 points)
    log_message "INFO" "  [3/3] Checking documentation..."
    if [[ -f "${REPO_DIR}/README.md" ]] || [[ -f "${REPO_DIR}/README" ]] || [[ -d "${REPO_DIR}/docs" ]]; then
      log_message "PASS" "  Documentation present."
    else
      deductions+=("-10: No README or docs found")
    fi

    # Calculate score
    for deduction in "${deductions[@]}"; do
      local val
      val=$(echo "$deduction" | grep -oP '-\d+' || echo "0")
      score=$((score + val))
    done
    if [[ $score -lt 0 ]]; then score=0; fi

    log_message "INFO" "  QA Score: ${score}/100 (threshold: 60)"
    for d in "${deductions[@]}"; do
      log_message "WARN" "    ${d}"
    done

    if [[ $score -lt 60 ]]; then
      log_message "ERROR" "QA Score ${score} is below simplified threshold of 60."
      return 1
    fi

    log_message "PASS" "QA Gate passed with score ${score}/100."
    return 0
  fi

  # Full QA scoring for service repos (backend/frontend/fullstack/agent)
  # 1. Container health (20 points)
  log_message "INFO" "  [1/5] Checking container health..."
  local container_health=true
  if command -v docker &>/dev/null; then
    local unhealthy
    unhealthy=$(docker ps --filter "name=${CURRENT_REPO}" --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -v "healthy\|Up " || true)
    if [[ -n "$unhealthy" ]]; then
      container_health=false
      deductions+=("-20: Unhealthy containers detected")
    fi
  fi

  # 2. Zero-trust compliance (20 points)
  log_message "INFO" "  [2/5] Verifying zero-trust compliance..."
  local zt_compliant=true
  local port
  port=$(jq -r '.port' "${PROFILE_FILE}")
  if ss -tlnp "sport = :${port}" 2>/dev/null | grep -qP "0\.0\.0\.0:${port}\s"; then
    zt_compliant=false
    deductions+=("-20: Service exposed on 0.0.0.0")
  fi

  # 3. Logging and monitoring setup (20 points)
  log_message "INFO" "  [3/5] Checking logging and monitoring..."
  local monitoring_ok=true
  if [[ -f "${REPO_DIR}/docker-compose.yml" ]] || [[ -f "${REPO_DIR}/docker-compose.generated.yml" ]]; then
    if ! grep -q "logging" "${REPO_DIR}/docker-compose.generated.yml" 2>/dev/null; then
      if ! grep -q "logging" "${REPO_DIR}/docker-compose.yml" 2>/dev/null; then
        monitoring_ok=false
        deductions+=("-10: No logging configuration")
      fi
    fi
  fi

  # 4. Resource limits (20 points)
  log_message "INFO" "  [4/5] Checking resource limits..."
  local resources_ok=true
  if [[ -f "${REPO_DIR}/docker-compose.yml" ]] || [[ -f "${REPO_DIR}/docker-compose.generated.yml" ]]; then
    local compose_file="${REPO_DIR}/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
      compose_file="${REPO_DIR}/docker-compose.generated.yml"
    fi
    if ! grep -q "mem_limit\|memory:" "$compose_file" 2>/dev/null; then
      resources_ok=false
      deductions+=("-10: No memory limits configured")
    fi
    if ! grep -q "cpus\|cpu_limit" "$compose_file" 2>/dev/null; then
      resources_ok=false
      deductions+=("-10: No CPU limits configured")
    fi
  fi

  # 5. Security posture (20 points)
  log_message "INFO" "  [5/5] Checking security posture..."
  local security_ok=true
  if [[ -f "${REPO_DIR}/docker-compose.yml" ]] || [[ -f "${REPO_DIR}/docker-compose.generated.yml" ]]; then
    local compose_file="${REPO_DIR}/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
      compose_file="${REPO_DIR}/docker-compose.generated.yml"
    fi
    if ! grep -q "no-new-privileges\|cap_drop" "$compose_file" 2>/dev/null; then
      security_ok=false
      deductions+=("-10: No security hardening (cap_drop, no-new-privileges)")
    fi
    if ! grep -q "healthcheck" "$compose_file" 2>/dev/null; then
      security_ok=false
      deductions+=("-10: No healthcheck configured")
    fi
  fi

  # Calculate score
  for deduction in "${deductions[@]}"; do
    local val
    val=$(echo "$deduction" | grep -oP '-\d+' || echo "0")
    score=$((score + val))
  done
  if [[ $score -lt 0 ]]; then score=0; fi

  log_message "INFO" "  QA Score: ${score}/100"
  for d in "${deductions[@]}"; do
    log_message "WARN" "    ${d}"
  done

  if [[ $score -lt $QA_SCORE_PASS ]]; then
    log_message "ERROR" "QA Score ${score} is below minimum threshold of ${QA_SCORE_PASS}."
    log_message "ERROR" "This is a NON-BYPASSABLE gate. Fix the issues and re-run."
    return 1
  fi

  log_message "PASS" "QA Gate passed with score ${score}/100 (threshold: ${QA_SCORE_PASS})."
  return 0
}

# ---------------------------------------------------------------------------
# Phase 13: Route Registration
# ---------------------------------------------------------------------------
phase_13_register() {
  log_message "INFO" "Registering routes in route-registry..."

  if ! load_json "$ROUTE_REGISTRY"; then
    log_message "WARN" "Route registry unavailable. Registration is best-effort."
    return 0
  fi

  # Check if route already exists
  local existing
  existing=$(jq -r ".routes[] | select(.id == \"${CURRENT_REPO}\") | .id" "$ROUTE_REGISTRY" 2>/dev/null || echo "")

  if [[ -n "$existing" ]]; then
    log_message "INFO" "  Route '${CURRENT_REPO}' already registered in route-registry.json"
  else
    log_message "WARN" "  Route '${CURRENT_REPO}' not found in route-registry.json"
    log_message "WARN" "  Add it manually or update the enforcement file."
  fi

  # Verify nginx symlink is active
  if [[ -L "${DEPLOY_NGINX_ENABLED}/${CURRENT_REPO}.conf" ]]; then
    log_message "INFO" "  Nginx route symlink is active."
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Phase 14: Finalize
# ---------------------------------------------------------------------------
phase_14_finalize() {
  log_message "INFO" "Finalizing pipeline..."

  # Verify all prior phases passed (skip phase 14 — it is currently executing)
  local all_passed=true
  local phases_completed=0
  for phase in "${PHASE_LABELS[@]}"; do
    if [[ "$phase" == "14_finalize" ]]; then
      continue  # Skip current phase — phase 14 is still "running" during its own execution
    fi
    if [[ "${PHASE_STATUS[$phase]}" != "passed" ]]; then
      all_passed=false
      log_message "WARN" "  Phase ${phase}: ${PHASE_STATUS[$phase]}"
    else
      phases_completed=$((phases_completed + 1))
    fi
  done

  if [[ "$all_passed" == "true" ]]; then
    log_message "PASS" "Pipeline complete: ${phases_completed}/13 prior phases passed — all green."
  else
    log_message "WARN" "Pipeline completed with failures: only ${phases_completed}/13 prior phases passed."
  fi

  # Update metrics
  local duration_seconds=$(( $(date +%s) - $(date -d "${RUN_STARTED}" +%s 2>/dev/null || date +%s) ))

  # Build phases_status JSON for the run record
  local phases_json="{}"
  for phase in "${PHASE_LABELS[@]}"; do
    phases_json=$(echo "$phases_json" | jq --arg p "$phase" --arg s "${PHASE_STATUS[$phase]}" '. + {($p): $s}')
  done
  local verified_at
  verified_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Save completed run to state
  local tmp_list
  tmp_list=$(mktemp)
  local existing_list
  existing_list=$(jq '.completed_runs.last_10 // []' "$REPO_ROUTER_STATE" 2>/dev/null || echo "[]")
  echo "$existing_list" | jq \
    --arg id "$RUN_ID" \
    --arg repo "$CURRENT_REPO" \
    --arg ts "$verified_at" \
    --arg started "$RUN_STARTED" \
    --argjson duration "$duration_seconds" \
    --arg result "$(if [[ "$all_passed" == "true" ]]; then echo "success"; else echo "partial"; fi)" \
    --argjson phases_completed "$phases_completed" \
    --argjson phases_status "$phases_json" \
    --arg verified_at "$verified_at" \
    '.[:9] | [{ run_id: $id, repo: $repo, completed_at: $ts, started_at: $started, duration_seconds: $duration, result: $result, phases_completed: $phases_completed, phases_status: $phases_status, verified_at: $verified_at }] + .' \
    > "$tmp_list"

  local existing_completed
  existing_completed=$(jq '.completed_runs.total_completed // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo "0")
  local new_completed=$((existing_completed + 1))

  jq \
    --argjson new_list "$(cat "$tmp_list")" \
    --argjson new_count "$new_completed" \
    '.completed_runs.last_10 = $new_list | .completed_runs.total_completed = $new_count' \
    "$REPO_ROUTER_STATE" > "$REPO_ROUTER_STATE.tmp" && mv "$REPO_ROUTER_STATE.tmp" "$REPO_ROUTER_STATE"

  rm -f "$tmp_list"

  log_message "INFO" "Run ${RUN_ID} finalized (${duration_seconds}s)."
  log_message "INFO" "Total completed runs: ${new_completed}"

  # Run role activator for this repo
  local role_activator="${REPO_ROUTER_ENFORCEMENT}/role-activator.sh"
  if [[ -x "$role_activator" ]]; then
    log_message "INFO" "Activating ecosystem role for ${CURRENT_REPO}..."
    if "$role_activator" --repo "$CURRENT_REPO" >> "${REPO_ROUTER_LOGS}/role-activator.log" 2>&1; then
      log_message "PASS" "Ecosystem role activated for ${CURRENT_REPO}."
    else
      log_message "WARN" "Role activation completed with warnings for ${CURRENT_REPO}."
    fi
  fi

  # Generate summary
  log_message "INFO" ""
  log_message "INFO" "=========================================="
  log_message "INFO" "  DEPLOYMENT SUMMARY"
  log_message "INFO" "=========================================="
  log_message "INFO" "  Repo:       ${CURRENT_REPO}"
  log_message "INFO" "  Run ID:     ${RUN_ID}"
  log_message "INFO" "  Duration:   ${duration_seconds}s"
  log_message "INFO" "  Result:     $(if [[ "$all_passed" == "true" ]]; then echo "SUCCESS"; else echo "PARTIAL"; fi)"
  log_message "INFO" "=========================================="

  return 0
}

# ---------------------------------------------------------------------------
# Intake command (Phase 01 only)
# ---------------------------------------------------------------------------
cmd_intake() {
  local repo_input="$1"
  if [[ -z "$repo_input" ]]; then
    log_message "ERROR" "Usage: $0 intake <repo-url-or-path>"
    exit 1
  fi

  load_state
  phase_01_intake "$repo_input" || exit 1
  save_state
  log_message "INFO" "Intake complete for '${CURRENT_REPO}'."
}

# ---------------------------------------------------------------------------
# Deploy command (Phases 01 through 14)
# ---------------------------------------------------------------------------
cmd_deploy() {
  local repo_input="$1"
  if [[ -z "$repo_input" ]]; then
    log_message "ERROR" "Usage: $0 deploy <repo-name>"
    exit 1
  fi

  load_state

  # Phase 01: Intake
  PHASE_STATUS["01_intake"]="running"
  phase_01_intake "$repo_input" || { PHASE_STATUS["01_intake"]="failed"; exit 1; }
  PHASE_STATUS["01_intake"]="passed"

  for phase_num in $(seq 2 $TOTAL_PHASES); do
    local phase_name="${PHASE_LABELS[$((phase_num - 1))]}"

    if ! run_phase "$phase_num"; then
      PHASE_STATUS["$phase_name"]="failed"
      log_message "ERROR" "Pipeline halted at phase ${phase_num}."
      log_message "ERROR" "Run '${BOLD}$0 deploy ${repo_input}${NC}' after fixing the issue."

      # Save partial state
      save_state
      exit 1
    fi
  done

  save_state
  log_message "PASS" "Full deployment pipeline completed for '${CURRENT_REPO}'."
}

# ---------------------------------------------------------------------------
# Rollback command
# ---------------------------------------------------------------------------
cmd_rollback() {
  local repo_name="$1"
  if [[ -z "$repo_name" ]]; then
    log_message "ERROR" "Usage: $0 rollback <repo-name>"
    exit 1
  fi

  log_message "WARN" "=========================================="
  log_message "WARN" "  ROLLBACK: ${repo_name}"
  log_message "WARN" "=========================================="

  REPO_DIR="${DEPLOY_BASE}/${repo_name}"

  if [[ ! -d "$REPO_DIR" ]]; then
    log_message "ERROR" "Repository directory not found: ${REPO_DIR}"
    exit 1
  fi

  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    log_message "ERROR" "Not a git repository: ${REPO_DIR}"
    exit 1
  fi

  log_message "INFO" "Fetching previous version..."
  cd "$REPO_DIR"

  # Check if there's a previous tag or commit to rollback to
  local rollback_target=""
  if git tag | sort -V | tail -2 | head -1 | grep -q .; then
    rollback_target=$(git tag | sort -V | tail -2 | head -1)
  elif git log --oneline -2 --skip=1 --format="%H" | head -1 | grep -q .; then
    rollback_target=$(git log --oneline -2 --skip=1 --format="%H" | head -1)
  else
    log_message "ERROR" "No previous version found to rollback to."
    exit 1
  fi

  log_message "INFO" "Rolling back to: ${rollback_target}"

  # Stop current services
  log_message "INFO" "Stopping current services..."
  if command -v docker-compose &>/dev/null && [[ -f "${REPO_DIR}/docker-compose.yml" ]]; then
    docker-compose -f "${REPO_DIR}/docker-compose.yml" down 2>/dev/null || true
  fi

  if command -v pm2 &>/dev/null && pm2 list 2>/dev/null | grep -q "$repo_name"; then
    pm2 delete "$repo_name" 2>/dev/null || true
    pm2 save 2>/dev/null || true
  fi

  # Git rollback
  git checkout "$rollback_target" 2>&1 | log_message "DEBUG"
  log_message "INFO" "Git checkout to ${rollback_target} complete."

  # Restart with rolled-back code
  if [[ -f "${REPO_DIR}/docker-compose.yml" ]]; then
    docker-compose -f "${REPO_DIR}/docker-compose.yml" up -d 2>&1 | tail -3
    log_message "INFO" "Docker services restarted from rolled-back version."
  fi

  if command -v pm2 &>/dev/null && [[ -f "${REPO_DIR}/ecosystem.config.js" ]]; then
    pm2 start "${REPO_DIR}/ecosystem.config.js" --env production 2>&1 | tail -3
    pm2 save
    log_message "INFO" "PM2 process restarted from rolled-back version."
  fi

  log_message "PASS" "Rollback to ${rollback_target} completed for '${repo_name}'."
}

# ---------------------------------------------------------------------------
# Status command
# ---------------------------------------------------------------------------
cmd_status() {
  local repo_name="${1:-}"
  load_state

  if [[ -n "$repo_name" ]]; then
    local profile
    profile=$(jq -r ".repo_profiles.\"${repo_name}\" // empty" "$REPO_ROUTER_STATE" 2>/dev/null)

    if [[ -z "$profile" ]]; then
      log_message "ERROR" "Repository '${repo_name}' not found in state."
      exit 1
    fi

    local status
    local phase
    local last_deployed
    status=$(echo "$profile" | jq -r '.status')
    phase=$(echo "$profile" | jq -r '.current_phase')
    last_deployed=$(echo "$profile" | jq -r '.last_deployed // "never"')

    echo ""
    echo -e "${BOLD}Repository: ${repo_name}${NC}"
    echo "  Status:        ${status}"
    echo "  Phase:         ${phase}/${TOTAL_PHASES}"
    echo "  Last Deployed: ${last_deployed}"
    echo "  Type:          $(echo "$profile" | jq -r '.repo_type')"
    echo "  Node:          $(echo "$profile" | jq -r '.node')"
    echo "  Port:          $(echo "$profile" | jq -r '.port')"
    echo ""
  else
    # Summary of all repos
    echo ""
    echo -e "${BOLD}Repo Router - All Repository Statuses${NC}"
    echo "=========================================="
    echo ""

    local repos
    repos=$(jq -r '.repo_profiles | to_entries[] | "\(.key)|\(.value.status)|\(.value.current_phase)|\(.value.node)|\(.value.repo_type)"' "$REPO_ROUTER_STATE" 2>/dev/null || echo "")

    if [[ -z "$repos" ]]; then
      log_message "INFO" "No repositories registered in state."
      return 0
    fi

    printf "%-25s %-15s %-8s %-10s %-12s\n" "NAME" "STATUS" "PHASE" "NODE" "TYPE"
    printf "%-25s %-15s %-8s %-10s %-12s\n" "-------------------------" "---------------" "--------" "----------" "------------"
    echo "$repos" | while IFS='|' read -r name status phase node rtype; do
      printf "%-25s %-15s %-8s %-10s %-12s\n" "$name" "$status" "${phase}/${TOTAL_PHASES}" "$node" "$rtype"
    done
    echo ""

    local total
    total=$(echo "$repos" | wc -l)
    local deployed
    deployed=$(echo "$repos" | grep "|deployed" | wc -l || echo 0)
    local active_runs_count
    active_runs_count=$(jq '.active_runs.total_active // 0' "$REPO_ROUTER_STATE")
    local completed
    completed=$(jq '.completed_runs.total_completed // 0' "$REPO_ROUTER_STATE")

    echo "Total: ${total} | Deployed: ${deployed} | Active Runs: ${active_runs_count} | Completed Deployments: ${completed}"
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Drift Check command
# ---------------------------------------------------------------------------
cmd_drift_check() {
  log_message "INFO" "Running drift detection on all managed repos..."

  load_state

  local repos
  repos=$(jq -r '.registered_repos[]' "$REPO_ROUTER_STATE" 2>/dev/null || echo "")

  if [[ -z "$repos" ]]; then
    log_message "INFO" "No registered repos to check."
    return 0
  fi

  local drift_found=false
  echo ""
  echo -e "${BOLD}Drift Detection Report${NC}"
  echo "=========================================="

  for repo_name in $repos; do
    local repo_dir="${DEPLOY_BASE}/${repo_name}"
    local drifts=()

    log_message "INFO" "Checking ${repo_name}..."

    # Check if directory exists
    if [[ ! -d "$repo_dir" ]]; then
      drifts+=("MISSING: Repository directory not found at ${repo_dir}")
    else
      # Check git drift
      if [[ -d "${repo_dir}/.git" ]]; then
        cd "$repo_dir"
        git fetch --quiet 2>/dev/null || true
        local behind
        behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "0")
        local ahead
        ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo "0")

        if [[ "$behind" -gt 0 ]]; then
          drifts+=("GIT: ${behind} commit(s) behind origin/main")
          drift_found=true
        fi
        if [[ "$ahead" -gt 0 ]]; then
          drifts+=("GIT: ${ahead} commit(s) ahead of origin/main (unpushed changes)")
          drift_found=true
        fi
      fi

      # Check port drift
      local allocated_port
      allocated_port=$(jq -r ".services.\"${repo_name}\".port // 0" "$PORT_ALLOCATION_TABLE" 2>/dev/null || echo "0")
      if [[ "$allocated_port" != "0" ]] && [[ "$allocated_port" != "null" ]]; then
        local port_in_use=false
        if ss -tlnp "sport = :${allocated_port}" 2>/dev/null | grep -q "${allocated_port}"; then
          port_in_use=true
        fi
        if [[ "$port_in_use" == "false" ]]; then
          drifts+=("PORT: Allocated port ${allocated_port} is not listening")
        fi
      fi

      # Check Docker drift
      if command -v docker &>/dev/null; then
        local container_count
        container_count=$(docker ps --filter "name=${repo_name}" --format '{{.Names}}' 2>/dev/null | wc -l)
        if [[ "$container_count" -eq 0 ]] && jq -e ".repo_profiles.\"${repo_name}\".deployment_strategy // \"\" | test(\"docker\")" "$REPO_ROUTER_STATE" &>/dev/null; then
          drifts+=("DOCKER: Expected Docker containers but none running")
          drift_found=true
        fi
      fi

      # Check PM2 drift
      if command -v pm2 &>/dev/null; then
        if ! pm2 list 2>/dev/null | grep -q "$repo_name"; then
          if jq -e ".repo_profiles.\"${repo_name}\".status == \"deployed\"" "$REPO_ROUTER_STATE" &>/dev/null; then
            drifts+=("PM2: Expected PM2 process but not found")
            drift_found=true
          fi
        fi
      fi
    fi

    # Report drifts for this repo
    if [[ ${#drifts[@]} -gt 0 ]]; then
      echo -e "${YELLOW}  ${repo_name}:${NC}"
      for drift in "${drifts[@]}"; do
        echo -e "${RED}    ! ${drift}${NC}"
      done
    else
      echo -e "${GREEN}  ${repo_name}: OK${NC}"
    fi
  done

  echo ""
  if [[ "$drift_found" == "false" ]]; then
    log_message "PASS" "No drift detected across all managed repos."
  else
    log_message "WARN" "Drift detected. Review and remediate as needed."
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Dashboard command
# ---------------------------------------------------------------------------
cmd_dashboard() {
  load_state

  clear 2>/dev/null || true

  echo ""
  echo -e "${BOLD}${CYAN}================================================================${NC}"
  echo -e "${BOLD}${CYAN}  WHEELER REPO ROUTER - SYSTEM DASHBOARD${NC}"
  echo -e "${BOLD}${CYAN}================================================================${NC}"
  echo ""

  # System status
  local sys_status
  sys_status=$(jq -r '.system.status' "$REPO_ROUTER_STATE" 2>/dev/null || echo "unknown")
  local last_update
  last_update=$(jq -r '.metadata.last_updated // "never"' "$REPO_ROUTER_STATE" 2>/dev/null || echo "never")

  echo -e "${BOLD}System Status:${NC} ${GREEN}${sys_status}${NC}"
  echo -e "${BOLD}Last Updated:${NC}  ${last_update}"
  echo -e "${BOLD}Node:${NC}          ${NODE_HOSTNAME} (${NODE_TYPE})"
  echo ""

  # Active runs
  local active_count
  active_count=$(jq '.active_runs.total_active // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  echo -e "${BOLD}Active Runs:${NC}  ${active_count}"

  if [[ "$active_count" -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}Active Pipelines:${NC}"
    jq -r '.active_runs.runs[] | "  \(.run_id) | \(.repo) | Phase \(.phase)/14"' "$REPO_ROUTER_STATE" 2>/dev/null || true
  fi

  echo ""

  # Repo status summary
  echo -e "${BOLD}Repository Overview:${NC}"
  echo ""

  local repos
  repos=$(jq -r '.repo_profiles | to_entries[] | "\(.key)|\(.value.status)|\(.value.current_phase)|\(.value.node)|\(.value.port)"' "$REPO_ROUTER_STATE" 2>/dev/null || echo "")

  if [[ -n "$repos" ]]; then
    printf "  %-25s %-15s %-8s %-10s %-8s\n" "REPO" "STATUS" "PHASE" "NODE" "PORT"
    printf "  %-25s %-15s %-8s %-10s %-8s\n" "-------------------------" "---------------" "--------" "----------" "--------"
    echo "$repos" | while IFS='|' read -r name status phase node port; do
      local color="${GREEN}"
      [[ "$status" == "pending_deploy" ]] && color="${YELLOW}"
      [[ "$status" == "failed" ]] && color="${RED}"
      printf "  ${color}%-25s %-15s %-8s %-10s %-8s${NC}\n" "$name" "$status" "${phase}/${TOTAL_PHASES}" "$node" "${port}"
    done
  else
    echo "  No repositories registered."
  fi

  echo ""

  # Metrics
  echo -e "${BOLD}Pipeline Metrics:${NC}"
  local total_deploys
  total_deploys=$(jq '.metrics.total_deployments // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  local successful
  successful=$(jq '.metrics.successful_deployments // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  local failed
  failed=$(jq '.metrics.failed_deployments // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  local rollbacks
  rollbacks=$(jq '.metrics.total_rollbacks // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  local avg_time
  avg_time=$(jq '.metrics.average_deploy_time_seconds // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  local avg_qa
  avg_qa=$(jq '.metrics.average_qa_score // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)

  echo "  Total Deployments:    ${total_deploys}"
  echo "  Successful:           ${successful}"
  echo -e "  Failed:               ${RED}${failed}${NC}"
  echo "  Rollbacks:            ${rollbacks}"
  echo "  Avg Deploy Time:      ${avg_time}s"
  echo -e "  Avg QA Score:         ${CYAN}${avg_qa}/100${NC}"
  echo ""

  # Use the port-allocation-table for quota info
  if [[ -f "$PORT_ALLOCATION_TABLE" ]]; then
    local total_ports
    total_ports=$(jq '.services | length' "$PORT_ALLOCATION_TABLE" 2>/dev/null || echo 0)
    echo "  Services in Port Table: ${total_ports}"
  fi

  echo ""
  echo -e "${BOLD}${CYAN}================================================================${NC}"
  echo ""

  # Recent completed runs
  local recent_count
  recent_count=$(jq '.completed_runs.total_completed // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  if [[ "$recent_count" -gt 0 ]]; then
    echo -e "${BOLD}Recent Completed Runs (last 5):${NC}"
    jq -r '.completed_runs.last_10[:5][] | "  [\(.completed_at)] \(.repo) - \(.result) (\(.duration_seconds)s)"' "$REPO_ROUTER_STATE" 2>/dev/null || true
    echo ""
  fi

  # Blocked repos
  local blocked_count
  blocked_count=$(jq '.blocked_repos.total_blocked // 0' "$REPO_ROUTER_STATE" 2>/dev/null || echo 0)
  if [[ "$blocked_count" -gt 0 ]]; then
    echo -e "${BOLD}Blocked Repos:${NC}"
    jq -r '.blocked_repos.entries[] | "  \(.repo): \(.reason)"' "$REPO_ROUTER_STATE" 2>/dev/null || true
    echo ""
  fi

  echo -e "${BOLD}Usage:${NC}"
  echo "  ./repo-router.sh intake <url|path>   Intake a repository"
  echo "  ./repo-router.sh deploy <name>        Deploy with full pipeline"
  echo "  ./repo-router.sh rollback <name>      Rollback to previous version"
  echo "  ./repo-router.sh status [name]        Show pipeline status"
  echo "  ./repo-router.sh drift-check          Run drift detection"
  echo "  ./repo-router.sh dashboard            Show this dashboard"
  echo ""
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------
main() {
  local command="${1:-help}"
  shift 2>/dev/null || true

  case "$command" in
    intake)
      cmd_intake "$@"
      ;;
    deploy)
      cmd_deploy "$@"
      ;;
    rollback)
      cmd_rollback "$@"
      ;;
    status)
      cmd_status "$@"
      ;;
    drift-check|drift)
      cmd_drift_check
      ;;
    dashboard|dash)
      cmd_dashboard
      ;;
    help|--help|-h)
      echo "Wheeler Repo Router - Deployment Orchestrator"
      echo ""
      echo "Commands:"
      echo "  intake <url|path>    Intake a repository (Phase 01 only)"
      echo "  deploy <name>        Run full 14-phase deployment pipeline"
      echo "  rollback <name>      Rollback to previous version"
      echo "  status [name]        Show pipeline status for all or specific repo"
      echo "  drift-check          Run drift detection on all managed repos"
      echo "  dashboard            Print summary dashboard"
      echo ""
      echo "Non-bypassable gates:"
      echo "  Phase 03 - Security Scan"
      echo "  Phase 05 - Port Allocation"
      echo "  Phase 10 - Zero-Trust Validation"
      echo "  Phase 12 - QA Scorecard"
      echo ""
      echo "Configuration:"
      echo "  config/repo-router-config.sh    Main config file"
      echo "  enforcement/port-allocation-table.json  Port allocation table"
      echo "  enforcement/route-registry.json         Route registry"
      echo "  config/router-state.json                Pipeline state"
      echo ""
      echo "Templates:"
      echo "  templates/docker/              Docker Compose templates (5)"
      echo "  templates/pm2/                 PM2 templates (2)"
      echo "  templates/nginx/               Nginx route templates (3)"
      echo "  templates/monitoring/          Monitoring configs (3)"
      echo "  templates/fragments/           Compose fragments (3)"
      ;;
    *)
      log_message "ERROR" "Unknown command: ${command}"
      echo "Usage: $0 <intake|deploy|rollback|status|drift-check|dashboard>"
      exit 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main "$@"
