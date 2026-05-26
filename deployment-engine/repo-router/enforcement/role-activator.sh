#!/usr/bin/env bash
# =============================================================================
# Role Activator — Activates ingested repos with Wheeler ecosystem roles
# =============================================================================
# Reads role-assignments.json and activates each repo according to its role
# category (cli-path, api-registry, library-registry, knowledge-index, etc.)
#
# Usage:
#   ./role-activator.sh [--all] [--repo <name>] [--dry-run] [--status]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROUTER_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROLE_CONFIG="${REPO_ROUTER_BASE}/config/role-assignments.json"
STATE_FILE="${REPO_ROUTER_BASE}/config/router-state.json"
ACTIVATION_LOG="/var/log/repo-router/role-activator.log"
CLI_SYMLINK_DIR="/usr/local/bin"
KNOWLEDGE_INDEX="/opt/wheeler-knowledge-base"
SKILL_REGISTRY="/opt/wheeler-ai-skills"
API_REGISTRY="/opt/wheeler-api-registry"
LIBRARY_REGISTRY="/opt/wheeler-libraries"
DATA_FEED_DIR="/opt/wheeler-intel-feeds"

mkdir -p "$(dirname "$ACTIVATION_LOG")" "$KNOWLEDGE_INDEX" "$SKILL_REGISTRY" \
  "$API_REGISTRY" "$LIBRARY_REGISTRY" "$DATA_FEED_DIR"

log_msg() {
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "[$ts] $*" | tee -a "$ACTIVATION_LOG"
}

# Activate a CLI tool by creating PATH symlinks
activate_cli_path() {
  local repo_name="$1"
  local repo_path="$2"
  local role_data="$3"

  log_msg "ACTIVATE CLI: ${repo_name} at ${repo_path}"

  # Find executable entry points
  local activated=0

  # Check for bin entries in package.json
  if [[ -f "${repo_path}/package.json" ]]; then
    jq -r '.bin // {} | to_entries[]? | "\(.key):\(.value)"' "${repo_path}/package.json" 2>/dev/null | while IFS=':' read -r name binpath; do
      local target="${repo_path}/${binpath}"
      local link="${CLI_SYMLINK_DIR}/${name}"
      if [[ -f "$target" ]]; then
        ln -sf "$target" "$link" 2>/dev/null && log_msg "  LINK ${link} -> ${target}" && activated=1 || log_msg "  WARN Could not link ${name}"
      fi
    done
  fi

  # Check for Go binary after build
  if [[ -f "${repo_path}/${repo_name}" ]] && [[ -x "${repo_path}/${repo_name}" ]]; then
    ln -sf "${repo_path}/${repo_name}" "${CLI_SYMLINK_DIR}/${repo_name}" 2>/dev/null && log_msg "  LINK ${CLI_SYMLINK_DIR}/${repo_name} -> ${repo_path}/${repo_name}" && activated=1
  fi

  # Check Cargo target
  if [[ -f "${repo_path}/target/release/${repo_name}" ]] && [[ -x "${repo_path}/target/release/${repo_name}" ]]; then
    ln -sf "${repo_path}/target/release/${repo_name}" "${CLI_SYMLINK_DIR}/${repo_name}" 2>/dev/null && log_msg "  LINK ${CLI_SYMLINK_DIR}/${repo_name}" && activated=1
  fi

  # Generic: if main script exists, symlink the repo dir as a tool
  if [[ -f "${repo_path}/main.py" ]] || [[ -f "${repo_path}/index.js" ]] || [[ -f "${repo_path}/main.go" ]]; then
    log_msg "  TOOL ${repo_name} has entry point, available at ${repo_path}"
    activated=1
  fi

  if [[ "$activated" -eq 0 ]]; then
    log_msg "  INFO No executable entry point found. Repo available at: ${repo_path}"
  fi

  return 0
}

# Register as an API service
activate_api_registry() {
  local repo_name="$1"
  local repo_path="$2"
  local role_data="$3"

  log_msg "ACTIVATE API: ${repo_name}"

  local registry_entry="${API_REGISTRY}/${repo_name}.json"
  cat > "$registry_entry" <<EOF
{
  "name": "${repo_name}",
  "path": "${repo_path}",
  "role": "$(echo "$role_data" | jq -r '.ecosystem_role')",
  "category": "$(echo "$role_data" | jq -r '.category')",
  "description": "$(echo "$role_data" | jq -r '.description')",
  "capabilities": $(echo "$role_data" | jq '.capabilities'),
  "activated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  log_msg "  REGISTERED ${registry_entry}"
  return 0
}

# Register as a library
activate_library_registry() {
  local repo_name="$1"
  local repo_path="$2"
  local role_data="$3"

  log_msg "ACTIVATE LIBRARY: ${repo_name}"

  local registry_entry="${LIBRARY_REGISTRY}/${repo_name}.json"
  cat > "$registry_entry" <<EOF
{
  "name": "${repo_name}",
  "path": "${repo_path}",
  "role": "$(echo "$role_data" | jq -r '.ecosystem_role')",
  "category": "$(echo "$role_data" | jq -r '.category')",
  "description": "$(echo "$role_data" | jq -r '.description')",
  "capabilities": $(echo "$role_data" | jq '.capabilities'),
  "activated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  log_msg "  REGISTERED ${registry_entry}"
  return 0
}

# Index as knowledge base
activate_knowledge_index() {
  local repo_name="$1"
  local repo_path="$2"
  local role_data="$3"

  log_msg "ACTIVATE KNOWLEDGE: ${repo_name}"

  local index_dir="${KNOWLEDGE_INDEX}/${repo_name}"
  mkdir -p "$index_dir"

  # Index README and docs
  if [[ -f "${repo_path}/README.md" ]]; then
    cp "${repo_path}/README.md" "${index_dir}/README.md"
  fi

  # Generate index metadata
  cat > "${index_dir}/index.json" <<EOF
{
  "name": "${repo_name}",
  "path": "${repo_path}",
  "role": "$(echo "$role_data" | jq -r '.ecosystem_role')",
  "description": "$(echo "$role_data" | jq -r '.description')",
  "capabilities": $(echo "$role_data" | jq '.capabilities'),
  "integrations": $(echo "$role_data" | jq '.integrations'),
  "indexed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  # Count indexed files
  local file_count
  file_count=$(find "${repo_path}" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | wc -l)
  log_msg "  INDEXED ${repo_name}: ${file_count} files -> ${index_dir}"
  return 0
}

# Set up as a data feed
activate_data_feed() {
  local repo_name="$1"
  local repo_path="$2"
  local role_data="$3"

  log_msg "ACTIVATE DATA FEED: ${repo_name}"

  local feed_dir="${DATA_FEED_DIR}/${repo_name}"
  mkdir -p "$feed_dir"

  # Create symlink to data files
  ln -sf "$repo_path" "${feed_dir}/source" 2>/dev/null || true

  cat > "${feed_dir}/feed.json" <<EOF
{
  "name": "${repo_name}",
  "path": "${repo_path}",
  "role": "$(echo "$role_data" | jq -r '.ecosystem_role')",
  "description": "$(echo "$role_data" | jq -r '.description')",
  "capabilities": $(echo "$role_data" | jq '.capabilities'),
  "activated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "refresh_cron": "0 */6 * * *"
}
EOF

  log_msg "  FEED ${repo_name} activated at ${feed_dir}"
  return 0
}

# Register as a web service
activate_web_service() {
  local repo_name="$1"
  local repo_path="$2"
  local role_data="$3"

  log_msg "ACTIVATE WEB SERVICE: ${repo_name}"

  local registry_entry="${API_REGISTRY}/${repo_name}-web.json"
  cat > "$registry_entry" <<EOF
{
  "name": "${repo_name}",
  "path": "${repo_path}",
  "role": "web-app",
  "description": "$(echo "$role_data" | jq -r '.description')",
  "capabilities": $(echo "$role_data" | jq '.capabilities'),
  "activated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  log_msg "  REGISTERED web service: ${registry_entry}"
  return 0
}

# Register as AI skill source
activate_skill_registry() {
  local repo_name="$1"
  local repo_path="$2"
  local role_data="$3"

  log_msg "ACTIVATE SKILLS: ${repo_name}"

  local skill_dir="${SKILL_REGISTRY}/${repo_name}"
  mkdir -p "$skill_dir"
  ln -sf "$repo_path" "${skill_dir}/source" 2>/dev/null || true

  # Count skill files
  local skill_count
  skill_count=$(find "${repo_path}" -name "*.md" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l)

  cat > "${skill_dir}/registry.json" <<EOF
{
  "name": "${repo_name}",
  "path": "${repo_path}",
  "role": "ai-skill",
  "description": "$(echo "$role_data" | jq -r '.description')",
  "capabilities": $(echo "$role_data" | jq '.capabilities'),
  "skill_files": ${skill_count},
  "activated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  log_msg "  SKILLS ${repo_name}: ${skill_count} files -> ${skill_dir}"
  return 0
}

# Main activation function
activate_repo() {
  local repo_name="$1"
  local role_data

  role_data=$(jq -r ".roles[\"${repo_name}\"]" "$ROLE_CONFIG" 2>/dev/null)
  if [[ -z "$role_data" ]] || [[ "$role_data" == "null" ]]; then
    log_msg "SKIP ${repo_name}: No role assignment found"
    return 0
  fi

  local activation_type
  activation_type=$(echo "$role_data" | jq -r '.activation')
  local repo_path
  repo_path=$(echo "$role_data" | jq -r '.binary_path')

  if [[ ! -d "$repo_path" ]]; then
    log_msg "WARN ${repo_name}: Repo path not found: ${repo_path}"
    return 1
  fi

  case "$activation_type" in
    "cli-path")
      activate_cli_path "$repo_name" "$repo_path" "$role_data"
      ;;
    "api-registry")
      activate_api_registry "$repo_name" "$repo_path" "$role_data"
      ;;
    "library-registry")
      activate_library_registry "$repo_name" "$repo_path" "$role_data"
      ;;
    "knowledge-index")
      activate_knowledge_index "$repo_name" "$repo_path" "$role_data"
      ;;
    "data-feed")
      activate_data_feed "$repo_name" "$repo_path" "$role_data"
      ;;
    "web-service")
      activate_web_service "$repo_name" "$repo_path" "$role_data"
      ;;
    "skill-registry")
      activate_skill_registry "$repo_name" "$repo_path" "$role_data"
      ;;
    *)
      log_msg "WARN ${repo_name}: Unknown activation type: ${activation_type}"
      return 1
      ;;
  esac

  # Update router state with activation info
  if [[ -f "$STATE_FILE" ]]; then
    local tmp_state
    tmp_state=$(mktemp)
    jq --arg name "$repo_name" \
       --arg role "$(echo "$role_data" | jq -r '.ecosystem_role')" \
       --arg cat "$(echo "$role_data" | jq -r '.category')" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.repo_profiles[$name].ecosystem_role = $role |
        .repo_profiles[$name].role_category = $cat |
        .repo_profiles[$name].activated_at = $ts |
        .repo_profiles[$name].status = "active"' \
       "$STATE_FILE" > "$tmp_state" && mv "$tmp_state" "$STATE_FILE"
  fi

  log_msg "ACTIVATED ${repo_name} -> $(echo "$role_data" | jq -r '.ecosystem_role') ($(echo "$role_data" | jq -r '.category'))"
  return 0
}

# Status command
cmd_status() {
  echo ""
  echo "Role Activator — Repo Role Status"
  echo "=================================="
  echo ""

  jq -r '.roles | to_entries[] | "\(.key): \(.value.ecosystem_role) [\(.value.activation)] - \(.value.description)"' "$ROLE_CONFIG" 2>/dev/null | while IFS= read -r line; do
    local repo_name="${line%%:*}"
    local activated=""
    if jq -e ".repo_profiles[\"${repo_name}\"].status == \"active\"" "$STATE_FILE" &>/dev/null; then
      activated="ACTIVE"
    else
      activated="pending"
    fi
    echo "  [${activated}] ${line}"
  done

  echo ""
  echo "Activation directories:"
  echo "  CLI tools:     ${CLI_SYMLINK_DIR}"
  echo "  API registry:  ${API_REGISTRY}"
  echo "  Libraries:     ${LIBRARY_REGISTRY}"
  echo "  Knowledge:     ${KNOWLEDGE_INDEX}"
  echo "  Skills:        ${SKILL_REGISTRY}"
  echo "  Data feeds:    ${DATA_FEED_DIR}"
  echo ""
}

# Main
case "${1:-}" in
  --status|-s)
    cmd_status
    ;;
  --dry-run|-n)
    log_msg "DRY RUN — no changes will be made"
    for repo_name in $(jq -r '.roles | keys[]' "$ROLE_CONFIG" 2>/dev/null); do
      role_data=$(jq -r ".roles[\"${repo_name}\"]" "$ROLE_CONFIG")
      echo "  WOULD ACTIVATE: ${repo_name} -> $(echo "$role_data" | jq -r '.ecosystem_role') [$(echo "$role_data" | jq -r '.activation')]"
    done
    ;;
  --repo|-r)
    shift
    activate_repo "$1"
    ;;
  --all|-a|*)
    log_msg "============================================="
    log_msg " ROLE ACTIVATOR — Activating all repos"
    log_msg "============================================="
    total=0; activated=0; failed=0
    for repo_name in $(jq -r '.roles | keys[]' "$ROLE_CONFIG" 2>/dev/null); do
      total=$((total + 1))
      if activate_repo "$repo_name"; then
        activated=$((activated + 1))
      else
        failed=$((failed + 1))
      fi
    done
    log_msg "============================================="
    log_msg " ACTIVATION COMPLETE: ${activated} active / ${failed} failed / ${total} total"
    log_msg "============================================="
    ;;
esac
