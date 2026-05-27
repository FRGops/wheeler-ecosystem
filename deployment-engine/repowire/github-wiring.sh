#!/usr/bin/env bash
# =============================================================================
# Wheeler GitHub-Repowire Mesh Wiring
# Part of: Wheeler Brain OS Agent Army — GitHub Intelligence
# Server: AIOPS (100.121.230.28)
# Target: Repowire daemon at 127.0.0.1:8377
#
# Wires every Wheeler GitHub repo into the repowire agent mesh:
#   1. Discovers Wheeler repos via gh CLI (with fallbacks)
#   2. Creates per-repo .repowire/peers.yaml peer definitions
#   3. Installs git post-commit hooks that broadcast to repowire
#   4. Creates a sourceable PR-event notifier script
#   5. Registers all repos as live peers in the mesh
# =============================================================================

set -euo pipefail

REPOWIRE_API="${REPOWIRE_API:-http://127.0.0.1:8377}"
REPOWIRE_CLI="${REPOWIRE_CLI:-repowire}"
WHEELER_ORG="${WHEELER_ORG:-}"
BRIDGE_DOMAIN="github"
REPOWIRE_CIRCLE="${REPOWIRE_CIRCLE:-wheeler-github}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOWIRE_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── State file for tracking what we've processed ────────────────────────────
STATE_DIR="${REPOWIRE_DIR}/.github-wiring-state"
mkdir -p "$STATE_DIR"
PROCESSED_LOG="$STATE_DIR/processed-repos.txt"
REGISTERED_LOG="$STATE_DIR/registered-peers.txt"

# ── Helper functions ────────────────────────────────────────────────────────

log_info()  { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
log_ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
log_warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
log_step()  { printf "\n${CYAN}${BOLD}==> %s${NC}\n" "$*"; }
log_fatal() { log_error "$*"; exit 1; }

# ── Step 0: Dependency checks ───────────────────────────────────────────────

check_dependencies() {
    local missing=0

    if ! command -v gh &>/dev/null; then
        log_warn "gh CLI not found. Will use fallback repo discovery."
    fi

    if ! command -v "$REPOWIRE_CLI" &>/dev/null; then
        log_warn "repowire CLI not found on PATH. Will use HTTP API directly."
    fi

    if ! command -v curl &>/dev/null; then
        log_fatal "curl is required but not installed."
    fi

    if ! command -v git &>/dev/null; then
        log_fatal "git is required but not installed."
    fi

    log_ok "All core dependencies present (gh=$([ -x "$(command -v gh)" ] && echo yes || echo no), curl=yes, git=yes)."
}

# ── Step 1: Discover repos ──────────────────────────────────────────────────

discover_repos() {
    log_step "Step 1: Discovering Wheeler GitHub repositories"

    local repos_file="$STATE_DIR/discovered-repos.txt"
    > "$repos_file"

    # Strategy A: gh CLI (authenticated)
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        log_info "gh CLI is authenticated. Fetching repos..."

        # Try org scope first; fall back to user scope
        local repo_list=""
        if [[ -n "$WHEELER_ORG" ]]; then
            repo_list="$(gh repo list "$WHEELER_ORG" --limit 100 --json name,owner,description,url,isFork,visibility 2>/dev/null || true)"
        fi
        if [[ -z "$repo_list" || "$repo_list" == "[]" ]]; then
            repo_list="$(gh repo list --limit 100 --json name,owner,description,url,isFork,visibility 2>/dev/null || true)"
        fi

        if [[ -n "$repo_list" && "$repo_list" != "[]" ]]; then
            echo "$repo_list" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data:
    name = r.get('name', '')
    owner = r.get('owner', {}).get('login', 'unknown')
    desc = r.get('description', '') or ''
    url = r.get('url', '')
    is_fork = r.get('isFork', False)
    vis = r.get('visibility', 'unknown')
    print(f\"{owner}/{name}|{desc}|{url}|{is_fork}|{vis}\")
" 2>/dev/null >> "$repos_file" || true
        fi
    fi

    # Strategy B: GITHUB_TOKEN env var
    if [[ ! -s "$repos_file" && -n "${GITHUB_TOKEN:-}" ]]; then
        log_info "Trying GitHub API with GITHUB_TOKEN..."
        local api_result
        api_result="$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/user/repos?per_page=100&type=owner" 2>/dev/null || true)"
        echo "$api_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for r in data:
        name = r.get('name', '')
        owner = r.get('owner', {}).get('login', 'unknown')
        desc = r.get('description', '') or ''
        url = r.get('html_url', '')
        is_fork = r.get('fork', False)
        vis = 'public' if not r.get('private', True) else 'private'
        print(f\"{owner}/{name}|{desc}|{url}|{is_fork}|{vis}\")
except: pass
" 2>/dev/null >> "$repos_file" || true
    fi

    # Strategy C: Scan local filesystem for git repos with 'wheeler' in path
    if [[ ! -s "$repos_file" ]]; then
        log_warn "gh not authenticated and no GITHUB_TOKEN. Scanning local filesystem for git repos..."
        find /root -maxdepth 4 -name ".git" -type d 2>/dev/null | while read -r gitdir; do
            local repo_dir
            repo_dir="$(dirname "$gitdir")"
            local basename
            basename="$(basename "$repo_dir")"

            # Get remote origin if available
            local remote_url=""
            remote_url="$(cd "$repo_dir" && git config --get remote.origin.url 2>/dev/null || true)"

            # Skip non-Wheeler repos (node_modules, .claude worktrees, etc.)
            case "$basename" in
                node_modules|.claude|__pycache__|.git) continue ;;
            esac

            local owner="local"
            local repo_name="$basename"
            local visibility="local"

            if [[ "$remote_url" =~ github.com[:/]([^/]+)/([^/\.]+)(\.git)? ]]; then
                owner="${BASH_REMATCH[1]}"
                repo_name="${BASH_REMATCH[2]}"
                visibility="remote"
            fi

            echo "${owner}/${repo_name}|$(cd "$repo_dir" && git log -1 --format=%s 2>/dev/null || true)|${remote_url}|false|${visibility}" >> "$repos_file"
        done
    fi

    # Read results
    local count=0
    REPO_LIST=()
    REPO_OWNER_LIST=()
    REPO_DESC_LIST=()
    REPO_URL_LIST=()

    if [[ -s "$repos_file" ]]; then
        while IFS='|' read -r full_name desc url is_fork vis; do
            [[ -z "$full_name" ]] && continue
            local owner="${full_name%%/*}"
            local name="${full_name#*/}"
            REPO_LIST+=("$name")
            REPO_OWNER_LIST+=("$owner")
            REPO_DESC_LIST+=("$desc")
            REPO_URL_LIST+=("$url")
            count=$((count + 1))
        done < "$repos_file"
    fi

    if [[ $count -eq 0 ]]; then
        log_warn "No repos discovered via any strategy."
        log_info "You can set WHEELER_REPO_NAMES env var to a space-separated list."
        log_info "Example: WHEELER_REPO_NAMES='wheeler-brain-os wheeler-command-center' $0"

        # Fallback to env var
        if [[ -n "${WHEELER_REPO_NAMES:-}" ]]; then
            log_info "Using WHEELER_REPO_NAMES from environment."
            for r in $WHEELER_REPO_NAMES; do
                REPO_LIST+=("$r")
                REPO_OWNER_LIST+=("${WHEELER_ORG:-wheeler}")
                REPO_DESC_LIST+=("Wheeler GitHub repo")
                REPO_URL_LIST+=("https://github.com/${WHEELER_ORG:-wheeler}/$r")
            done
            count=${#REPO_LIST[@]}
        fi
    fi

    log_ok "Discovered $count repos."
    for ((i=0; i<${#REPO_LIST[@]}; i++)); do
        printf "  ${GREEN}%-30s${NC} %s\n" "${REPO_OWNER_LIST[$i]}/${REPO_LIST[$i]}" "${REPO_DESC_LIST[$i]:0:60}"
    done

    return $count
}

# ── Step 2: Peer ID helpers ─────────────────────────────────────────────────

sanitize_peer_name() {
    local name="$1"
    # GitHub repo names may have dots, underscores, hyphens — repowire peers use hyphens
    echo "github-$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
}

# ── Step 3: Create per-repo .repowire/peers.yaml ────────────────────────────

create_repowire_peer_yaml() {
    log_step "Step 3: Creating .repowire/peers.yaml for each repo"

    local created=0
    for ((i=0; i<${#REPO_LIST[@]}; i++)); do
        local repo_name="${REPO_LIST[$i]}"
        local repo_owner="${REPO_OWNER_LIST[$i]}"
        local repo_desc="${REPO_DESC_LIST[$i]}"
        local repo_url="${REPO_URL_LIST[$i]}"
        local peer_name
        peer_name="$(sanitize_peer_name "$repo_name")"
        local peer_dir="/root/$repo_name"

        # Check if repo exists locally
        local local_path=""
        if [[ -d "/root/$repo_name/.git" ]]; then
            local_path="/root/$repo_name"
        elif [[ -d "/opt/wheeler/$repo_name/.git" ]]; then
            local_path="/opt/wheeler/$repo_name"
        fi

        # Create .repowire directory inside the repo if it exists locally
        local peers_file=""
        if [[ -n "$local_path" ]]; then
            mkdir -p "$local_path/.repowire"
            peers_file="$local_path/.repowire/peers.yaml"
        else
            # Store in our state directory for reference
            peers_file="$STATE_DIR/peers/${repo_name}.yaml"
            mkdir -p "$(dirname "$peers_file")"
        fi

        cat > "$peers_file" <<YAML
# =============================================================================
# Repowire Peer Definition — ${repo_owner}/${repo_name}
# Generated by GitHub Wiring Script at ${TIMESTAMP}
# Part of: Wheeler Brain OS Agent Army
# =============================================================================

peer:
  name: "${peer_name}"
  display_name: "${repo_owner}/${repo_name}"
  circle: "${REPOWIRE_CIRCLE}"
  path: "${local_path:-/root/${repo_name}}"

metadata:
  domain: "github"
  source: "github-wiring-script"
  repo_url: "${repo_url}"
  repo_owner: "${repo_owner}"
  repo_name: "${repo_name}"
  description: "${repo_desc}"
  generated_at: "${TIMESTAMP}"
  bridge: "${BRIDGE_DOMAIN}"
  health_endpoint: "${REPOWIRE_API}/health"

# GitHub-specific context for the mesh
github:
  owner: "${repo_owner}"
  repo: "${repo_name}"
  url: "${repo_url}"
  default_branch: "master"
  webhook_events:
    - push
    - pull_request
    - check_run
    - issues

# Circle membership — extends Wheeler domain peer model
circles:
  primary: "${REPOWIRE_CIRCLE}"
  secondary:
    - wheeler-github-events
YAML

        log_ok "Created ${peers_file}"
        created=$((created + 1))
    done

    log_ok "Created $created peer definition files."
}

# ── Step 4: Install post-commit hook templates ──────────────────────────────

install_post_commit_hooks() {
    log_step "Step 4: Installing git post-commit hooks that broadcast to repowire"

    local installed=0
    local skipped=0

    for ((i=0; i<${#REPO_LIST[@]}; i++)); do
        local repo_name="${REPO_LIST[$i]}"
        local peer_name
        peer_name="$(sanitize_peer_name "$repo_name")"

        # Find the git hooks directory for this repo
        local hooks_dir=""
        if [[ -d "/root/$repo_name/.git/hooks" ]]; then
            hooks_dir="/root/$repo_name/.git/hooks"
        elif [[ -d "/opt/wheeler/$repo_name/.git/hooks" ]]; then
            hooks_dir="/opt/wheeler/$repo_name/.git/hooks"
        fi

        if [[ -z "$hooks_dir" ]]; then
            log_warn "$repo_name: no local .git/hooks directory — skipping hook install"
            skipped=$((skipped + 1))
            continue
        fi

        local hook_file="$hooks_dir/post-commit"
        local hook_broadcast="$STATE_DIR/hook-broadcast.sh"

        # Create the shared broadcast helper if it doesn't exist
        if [[ ! -f "$hook_broadcast" ]]; then
            cat > "$hook_broadcast" <<'HELPER'
#!/usr/bin/env bash
# repowire-git-broadcast — called by git post-commit hooks
# Broadcasts commit info to the repowire agent mesh.
# Usage: repowire-git-broadcast <peer_name> <repo_name> [repo_owner]

set -euo pipefail

REPOWIRE_API="${REPOWIRE_API:-http://127.0.0.1:8377}"
PEER_NAME="${1:-unknown}"
REPO_NAME="${2:-unknown}"
REPO_OWNER="${3:-unknown}"

# Gather commit info from git environment
COMMIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
COMMIT_MSG="$(git log -1 --format="%s" 2>/dev/null || echo "unknown")"
COMMIT_AUTHOR="$(git log -1 --format="%an" 2>/dev/null || echo "unknown")"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
FILES_CHANGED="$(git diff --name-only HEAD~1..HEAD 2>/dev/null | wc -l | tr -d ' ' || echo "0")"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Truncate commit message for broadcast (keep it concise)
COMMIT_MSG_TRUNC="${COMMIT_MSG:0:120}"

payload() {
    cat <<JSON
{
    "from_peer": "${PEER_NAME}",
    "text": "[git:commit] ${REPO_OWNER}/${REPO_NAME} | ${BRANCH} | ${COMMIT_HASH} | ${COMMIT_AUTHOR} | ${FILES_CHANGED} file(s) | ${COMMIT_MSG_TRUNC}",
    "type": "git.commit",
    "repo": "${REPO_OWNER}/${REPO_NAME}",
    "commit": "${COMMIT_HASH}",
    "branch": "${BRANCH}",
    "author": "${COMMIT_AUTHOR}",
    "files_changed": ${FILES_CHANGED},
    "timestamp": "${TIMESTAMP}"
}
JSON
}

curl -s -X POST "${REPOWIRE_API}/broadcast" \
    -H "Content-Type: application/json" \
    -d "$(payload)" \
    --connect-timeout 3 \
    --max-time 5 \
    -o /dev/null \
    -w "%{http_code}" 2>/dev/null | grep -q '2' || true
HELPER
            chmod +x "$hook_broadcast"
            log_ok "Created broadcast helper at $hook_broadcast"
        fi

        # Install or append to post-commit hook
        if [[ -f "$hook_file" ]]; then
            # Check if repowire is already wired
            if grep -q "repowire" "$hook_file" 2>/dev/null; then
                log_info "$repo_name: post-commit already has repowire wiring — skipping"
                skipped=$((skipped + 1))
                continue
            fi
            # Append to existing hook
            cat >> "$hook_file" <<HOOK

# --- Repowire mesh broadcast (added by wheeler-ecosystem-audit) ---
if command -v "$hook_broadcast" &>/dev/null; then
    "$hook_broadcast" "${peer_name}" "${repo_name}" "${REPO_OWNER_LIST[$i]}" &
fi
HOOK
        else
            # Create new post-commit hook
            cat > "$hook_file" <<HOOK
#!/bin/sh
# Repowire mesh broadcast — notifies the agent mesh on every commit
# Installed by Wheeler GitHub Wiring Script

REPOWIRE_API="${REPOWIRE_API}"

if command -v "$hook_broadcast" &>/dev/null; then
    "$hook_broadcast" "${peer_name}" "${repo_name}" "${REPO_OWNER_LIST[$i]}" &
fi
HOOK
            chmod +x "$hook_file"
        fi

        log_ok "$repo_name: post-commit hook installed at $hook_file"
        installed=$((installed + 1))
    done

    log_ok "Installed/updated $installed post-commit hooks."
    if [[ $skipped -gt 0 ]]; then
        log_info "$skipped repos skipped (already wired or no local checkout)."
    fi
}

# ── Step 5: Create PR event notifier script ─────────────────────────────────

create_pr_notifier() {
    log_step "Step 5: Creating PR event notifier script"

    local notifier_file="$STATE_DIR/repowire-pr-notify.sh"

    cat > "$notifier_file" <<'NOTIFIER'
#!/usr/bin/env bash
# =============================================================================
# repowire-pr-notify — Sourceable PR event notifier for Wheeler GitHub CI
# Part of: Wheeler Brain OS Agent Army — GitHub Intelligence
#
# Source this script in CI workflows to auto-notify the repowire mesh
# on PR events (opened, closed, merged, CI passing/failing).
#
# Usage:
#   source ./repowire-pr-notify.sh
#   repowire_pr_notify "opened" "owner/repo" "PR #42: Add feature" "https://github.com/owner/repo/pull/42"
#   repowire_pr_notify "ci:passed" "owner/repo" "CI green on PR #42" "https://github.com/owner/repo/actions/runs/123"
#
# Or from environment variables (GitHub Actions compatible):
#   export REPOWIRE_API="http://127.0.0.1:8377"
#   export GITHUB_REPOSITORY="owner/repo"
#   export GITHUB_REF="refs/pull/42/head"
#   export GITHUB_EVENT_NAME="pull_request"
#   # Then just run: repowire_pr_notify_from_env
# =============================================================================

set -euo pipefail

REPOWIRE_API="${REPOWIRE_API:-http://127.0.0.1:8377}"
PEER_PREFIX="${PEER_PREFIX:-github}"

# ── Sanitize repo name to peer name ─────────────────────────────────────────
_repo_to_peer() {
    local repo="$1"
    local name="${repo#*/}"
    echo "${PEER_PREFIX}-$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
}

# ── Build a GitHub API URL for the repo ─────────────────────────────────────
_repo_api_url() {
    local repo="$1"
    echo "https://api.github.com/repos/${repo}"
}

# ── Main notification function ──────────────────────────────────────────────
# Arguments:
#   $1 - action: opened | closed | merged | ci:passed | ci:failed | ci:running | review:requested | review:submitted
#   $2 - repo: "owner/name"
#   $3 - title: short description
#   $4 - url: link to the PR/action
#   $5 - (optional) details: extra JSON context
repowire_pr_notify() {
    local action="${1:-unknown}"
    local repo="${2:-unknown}"
    local title="${3:-}"
    local url="${4:-}"
    local details="${5:-}"

    local peer_name
    peer_name="$(_repo_to_peer "$repo")"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    # Map action to a readable alert level
    local severity="info"
    case "$action" in
        opened)           severity="info" ;;
        merged)           severity="success" ;;
        closed)           severity="warning" ;;
        "ci:failed")      severity="error" ;;
        "ci:passed")      severity="success" ;;
        "ci:running")     severity="info" ;;
        "review:requested") severity="info" ;;
        "review:submitted") severity="info" ;;
        *)                severity="info" ;;
    esac

    # Build the broadcast text
    local text="[github:${action}] ${repo} | ${title}"
    [[ -n "$url" ]] && text="${text} | ${url}"

    # Build JSON payload
    local payload
    payload="$(cat <<JSON
{
    "from_peer": "${peer_name}",
    "text": "${text}",
    "type": "github.${action}",
    "severity": "${severity}",
    "repo": "${repo}",
    "action": "${action}",
    "title": "${title}",
    "url": "${url}",
    "timestamp": "${timestamp}"
}
JSON
)"

    # Add extra details if provided
    if [[ -n "$details" ]]; then
        # Remove trailing } and append details
        payload="${payload%,*}}, \"details\": ${details}}"
    fi

    # Broadcast to repowire
    local http_code
    http_code="$(curl -s -X POST "${REPOWIRE_API}/broadcast" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --connect-timeout 5 \
        --max-time 10 \
        -o /dev/null \
        -w "%{http_code}" 2>/dev/null || echo "000")"

    if [[ "$http_code" =~ ^2 ]]; then
        echo "[repowire-pr-notify] OK (${http_code}): ${action} ${repo} — ${title}"
        return 0
    else
        echo "[repowire-pr-notify] WARN (${http_code}): broadcast failed for ${action} ${repo}" >&2
        return 1
    fi
}

# ── Environment-driven notification (GitHub Actions friendly) ──────────────
# Reads standard GITHUB_* env vars to auto-detect context.
repowire_pr_notify_from_env() {
    local repo="${GITHUB_REPOSITORY:-}"
    local event="${GITHUB_EVENT_NAME:-}"
    local ref="${GITHUB_REF:-}"
    local sha="${GITHUB_SHA:-}"
    local run_id="${GITHUB_RUN_ID:-}"

    if [[ -z "$repo" ]]; then
        echo "[repowire-pr-notify] ERROR: GITHUB_REPOSITORY not set" >&2
        return 1
    fi

    local title="Event: ${event}"
    local url=""
    local action="${event}"

    case "$event" in
        pull_request)
            # Try to extract PR info from GITHUB_REF
            local pr_number=""
            if [[ "$ref" =~ refs/pull/([0-9]+) ]]; then
                pr_number="${BASH_REMATCH[1]}"
                title="PR #${pr_number}"
                url="https://github.com/${repo}/pull/${pr_number}"
            fi
            # Check GITHUB_EVENT_PATH for action details
            if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
                local pr_action
                pr_action="$(python3 -c "
import json
with open('${GITHUB_EVENT_PATH}') as f:
    data = json.load(f)
print(data.get('action', 'opened'))
" 2>/dev/null || echo "opened")"
                action="pr:${pr_action}"
                local pr_title
                pr_title="$(python3 -c "
import json
with open('${GITHUB_EVENT_PATH}') as f:
    data = json.load(f)
    pr = data.get('pull_request', data.get('issue', {}))
    print(pr.get('title', '')[:200])
" 2>/dev/null || echo "")"
                [[ -n "$pr_title" ]] && title="${title}: ${pr_title}"
            else
                action="pr:triggered"
            fi
            ;;
        push)
            action="push"
            title="Push to ${ref}"
            url="https://github.com/${repo}/commit/${sha}"
            ;;
        check_run)
            action="ci:check"
            title="Check run: ${ref}"
            if [[ -n "$run_id" ]]; then
                url="https://github.com/${repo}/actions/runs/${run_id}"
            fi
            ;;
        workflow_run)
            action="workflow:${GITHUB_ACTION:-run}"
            title="Workflow: ${GITHUB_WORKFLOW:-unknown}"
            if [[ -n "$run_id" ]]; then
                url="https://github.com/${repo}/actions/runs/${run_id}"
            fi
            ;;
        issue_comment)
            action="comment"
            title="Comment on ${ref}"
            ;;
        *)
            action="event:${event}"
            title="GitHub event: ${event} on ${ref}"
            ;;
    esac

    repowire_pr_notify "$action" "$repo" "$title" "$url"
}

# ── Batch notify: send PR status summary ────────────────────────────────────
# Fetches all open PRs for a repo and broadcasts a summary.
repowire_pr_summary() {
    local repo="${1:-}"
    [[ -z "$repo" ]] && repo="${GITHUB_REPOSITORY:-}"
    [[ -z "$repo" ]] && { echo "Usage: repowire_pr_summary <owner/repo>" >&2; return 1; }

    local peer_name
    peer_name="$(_repo_to_peer "$repo")"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    # Try to get PR count via GitHub API if token is available
    local pr_count="?"
    local ci_status="?"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        pr_count="$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/${repo}/pulls?state=open&per_page=1" \
            -I 2>/dev/null | grep -i 'link:' | grep -oP 'page=\K[0-9]+' | tail -1 || echo "0")"
        # If no pagination, count them
        if [[ "$pr_count" == "?" ]]; then
            pr_count="$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/${repo}/pulls?state=open" \
                2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")"
        fi
    fi

    curl -s -X POST "${REPOWIRE_API}/broadcast" \
        -H "Content-Type: application/json" \
        -d "$(cat <<JSON
{
    "from_peer": "${peer_name}",
    "text": "[github:pr-summary] ${repo} | ${pr_count} open PRs | CI: ${ci_status}",
    "type": "github.pr-summary",
    "repo": "${repo}",
    "open_prs": ${pr_count},
    "timestamp": "${timestamp}"
}
JSON
)" \
        --connect-timeout 5 \
        --max-time 10 \
        -o /dev/null \
        -w "%{http_code}" 2>/dev/null || echo "000"
}

# ── If sourced, just define functions. If executed, run from env. ────────────
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced: just make functions available
    return 0 2>/dev/null || true
else
    # Being executed: try env-driven notification
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
        repowire_pr_notify_from_env
    else
        echo "repowire-pr-notify: sourced to expose functions, or provide GITHUB_REPOSITORY env var." >&2
        echo "" >&2
        echo "Available functions:" >&2
        echo "  repowire_pr_notify <action> <repo> <title> [url] [details]" >&2
        echo "  repowire_pr_notify_from_env     # reads GITHUB_* env vars" >&2
        echo "  repowire_pr_summary [repo]       # broadcast open PR summary" >&2
        echo "" >&2
        echo "Actions: opened | closed | merged | ci:passed | ci:failed | review:requested | review:submitted" >&2
        exit 1
    fi
fi
NOTIFIER

    chmod +x "$notifier_file"
    log_ok "Created PR notifier at $notifier_file"

    # Also create a symlink in the repowire directory
    ln -sf "$notifier_file" "${REPOWIRE_DIR}/repowire-pr-notify.sh"
    log_ok "Symlinked to ${REPOWIRE_DIR}/repowire-pr-notify.sh"
}

# ── Step 6: Create a CI workflow template ───────────────────────────────────

create_ci_workflow_template() {
    log_step "Step 6: Creating GitHub Actions workflow template for repowire notifications"

    local template_dir="$STATE_DIR/workflow-templates"
    mkdir -p "$template_dir"

    cat > "$template_dir/repowire-notify.yml" <<'YAML'
# =============================================================================
# Repowire Mesh Notification — GitHub Actions Workflow Template
# Install into: .github/workflows/repowire-notify.yml
# Part of: Wheeler Brain OS Agent Army — GitHub Intelligence
#
# Notifies the repowire agent mesh on PR events and CI results.
# =============================================================================

name: Repowire Mesh Notification

on:
  pull_request:
    types: [opened, closed, reopened, ready_for_review, review_requested]
  push:
    branches: [master, main]
  check_run:
    types: [completed]

jobs:
  notify-repowire:
    name: Notify Agent Mesh
    runs-on: ubuntu-latest
    # Only run if REPOWIRE_API is reachable (or in Wheeler CI runners)
    if: ${{ vars.REPOWIRE_ENABLED == 'true' || runner.name == 'wheeler' }}

    steps:
      - name: Notify repowire mesh on event
        run: |
          curl -s -X POST "${{ vars.REPOWIRE_API || 'http://100.121.230.28:8377' }}/broadcast" \
            -H "Content-Type: application/json" \
            -d "$(cat <<JSON
          {
            "from_peer": "github-${{ github.event.repository.name }}",
            "text": "[github:${{ github.event_name }}] ${{ github.repository }} | ${{ github.event.pull_request.title || github.event.head_commit.message }}",
            "type": "github.${{ github.event_name }}",
            "repo": "${{ github.repository }}",
            "ref": "${{ github.ref }}",
            "sha": "${{ github.sha }}",
            "actor": "${{ github.actor }}",
            "url": "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
          }
JSON
          )" \
            --connect-timeout 5 --max-time 10 || echo "repowire unreachable — skipping notification"
YAML

    log_ok "Created workflow template at $template_dir/repowire-notify.yml"
    log_info "Install into any repo's .github/workflows/ to enable CI→repowire notifications."
}

# ── Step 7: Register all repos as repowire peers ────────────────────────────

register_peers_with_daemon() {
    log_step "Step 7: Registering repos as repowire mesh peers"

    local registered=0
    local errors=0

    for ((i=0; i<${#REPO_LIST[@]}; i++)); do
        local repo_name="${REPO_LIST[$i]}"
        local repo_owner="${REPO_OWNER_LIST[$i]}"
        local peer_name
        peer_name="$(sanitize_peer_name "$repo_name")"

        # Check if already registered
        local existing
        existing="$(curl -s "$REPOWIRE_API/peers" --connect-timeout 3 --max-time 5 2>/dev/null \
            | python3 -c "import json,sys; data=json.load(sys.stdin); print(any(p.get('name')=='${peer_name}' for p in data))" 2>/dev/null || echo "false")"

        if [[ "$existing" == "True" ]]; then
            log_info "$peer_name already registered in mesh — updating metadata"
        fi

        # Register via repowire CLI if available, otherwise via HTTP API
        local repo_path=""
        [[ -d "/root/$repo_name" ]] && repo_path="/root/$repo_name"
        [[ -z "$repo_path" && -d "/opt/wheeler/$repo_name" ]] && repo_path="/opt/wheeler/$repo_name"

        if command -v "$REPOWIRE_CLI" &>/dev/null; then
            # Use CLI for proper peer registration
            if "$REPOWIRE_CLI" peer register "$peer_name" \
                --circle "$REPOWIRE_CIRCLE" \
                --path "${repo_path:-/root/$repo_name}" 2>/dev/null; then
                log_ok "$peer_name registered via repowire CLI"
                registered=$((registered + 1))
            else
                # If registration fails, try unregister first (could be stale)
                "$REPOWIRE_CLI" peer unregister "$peer_name" 2>/dev/null || true
                if "$REPOWIRE_CLI" peer register "$peer_name" \
                    --circle "$REPOWIRE_CIRCLE" \
                    --path "${repo_path:-/root/$repo_name}" 2>/dev/null; then
                    log_ok "$peer_name registered (after unregister) via repowire CLI"
                    registered=$((registered + 1))
                else
                    log_warn "$peer_name: CLI registration failed"
                    errors=$((errors + 1))
                fi
            fi
        else
            # Fall back to HTTP API — we can't directly register peers via HTTP,
            # but we can broadcast our existence
            log_warn "repowire CLI unavailable — peer registration requires CLI."
            log_info "Install repowire CLI or use: repowire peer register $peer_name --circle $REPOWIRE_CIRCLE"
            errors=$((errors + 1))
        fi

        # Log registration
        echo "${peer_name} ${repo_owner}/${repo_name} ${TIMESTAMP}" >> "$REGISTERED_LOG"
    done

    log_ok "Registered $registered peers in the mesh."
    if [[ $errors -gt 0 ]]; then
        log_warn "$errors peers could not be registered (see above)."
    fi
}

# ── Step 8: Create the consolidated GitHub peer directory ───────────────────

create_consolidated_peers_index() {
    log_step "Creating consolidated GitHub peers index"

    local index_file="$STATE_DIR/github-peers-index.yaml"

    cat > "$index_file" <<YAML
# =============================================================================
# Wheeler GitHub Peers Index
# Generated: ${TIMESTAMP}
# Bridge Domain: ${BRIDGE_DOMAIN}
# Circle: ${REPOWIRE_CIRCLE}
#
# Auto-discovered GitHub repos mapped to repowire peer identities.
# This index is consumed by the repowire-bridge and GitHub Intelligence agent.
# =============================================================================

bridge:
  name: "${BRIDGE_DOMAIN}"
  display_name: "GitHub Intelligence"
  circle: "${REPOWIRE_CIRCLE}"
  description: "Monitors Wheeler GitHub repos, PRs, CI, and issues"
  agent_skill: "github-intelligence"
  command_map:
    health: "curl ${REPOWIRE_API}/health"
    peers: "curl ${REPOWIRE_API}/peers"
    pr_notify: "source ${REPOWIRE_DIR}/repowire-pr-notify.sh && repowire_pr_notify"

peers:
YAML

    for ((i=0; i<${#REPO_LIST[@]}; i++)); do
        local repo_name="${REPO_LIST[$i]}"
        local repo_owner="${REPO_OWNER_LIST[$i]}"
        local repo_desc="${REPO_DESC_LIST[$i]}"
        local peer_name
        peer_name="$(sanitize_peer_name "$repo_name")"

        cat >> "$index_file" <<YAML
  ${peer_name}:
    name: "${peer_name}"
    display_name: "${repo_owner}/${repo_name}"
    circle: "${REPOWIRE_CIRCLE}"
    description: "${repo_desc}"
    repo_url: "https://github.com/${repo_owner}/${repo_name}"
    local_path: "$([ -d "/root/$repo_name" ] && echo "/root/$repo_name" || echo 'N/A')"

YAML
    done

    log_ok "Created consolidated index at $index_file"
}

# ── Step 9: Verify connectivity ─────────────────────────────────────────────

verify_mesh() {
    log_step "Verifying mesh connectivity"

    # Check repowire daemon
    local health_status
    health_status="$(curl -s "$REPOWIRE_API/health" --connect-timeout 5 --max-time 10 2>/dev/null || echo "")"

    if [[ -z "$health_status" ]]; then
        log_error "Repowire daemon is not reachable at $REPOWIRE_API"
        log_info "Start it with: repowire serve --host 127.0.0.1 --port 8377"
        return 1
    fi

    local daemon_status
    daemon_status="$(echo "$health_status" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")"
    log_ok "Repowire daemon status: ${daemon_status}"

    # List peers
    local peers_json
    peers_json="$(curl -s "$REPOWIRE_API/peers" --connect-timeout 5 --max-time 10 2>/dev/null || echo "[]")"
    local peer_count
    peer_count="$(echo "$peers_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")"
    log_ok "Peers currently in mesh: $peer_count"

    if [[ $peer_count -gt 0 ]]; then
        echo "$peers_json" | python3 -c "
import json, sys
peers = json.load(sys.stdin)
for p in peers:
    name = p.get('name', '?')
    circle = p.get('circle', '?')
    status = p.get('status', '?')
    print(f'  {name:<35} circle={circle:<20} status={status}')
" 2>/dev/null || true
    fi

    # Test broadcast
    log_info "Testing broadcast..."
    local broadcast_code
    broadcast_code="$(curl -s -X POST "$REPOWIRE_API/broadcast" \
        -H "Content-Type: application/json" \
        -d "$(cat <<JSON
{
    "from_peer": "github-wiring-script",
    "text": "[github:wiring] GitHub-Repowire mesh wiring complete at ${TIMESTAMP} | ${#REPO_LIST[@]} repos wired",
    "type": "github.wiring.complete",
    "repo_count": ${#REPO_LIST[@]},
    "timestamp": "${TIMESTAMP}"
}
JSON
)" \
        --connect-timeout 5 \
        --max-time 10 \
        -o /dev/null \
        -w "%{http_code}" 2>/dev/null || echo "000")"

    if [[ "$broadcast_code" =~ ^2 ]]; then
        log_ok "Test broadcast successful (HTTP $broadcast_code)"
    else
        log_warn "Test broadcast returned HTTP $broadcast_code"
    fi

    return 0
}

# ── Summary function ────────────────────────────────────────────────────────

print_summary() {
    local repo_count=${#REPO_LIST[@]}

    printf "\n"
    printf "╔══════════════════════════════════════════════════════════════════╗\n"
    printf "║       Wheeler GitHub-Repowire Mesh Wiring Complete              ║\n"
    printf "╠══════════════════════════════════════════════════════════════════╣\n"
    printf "║ Repowire daemon:  ${REPOWIRE_API}%-33s║\n" ""
    printf "║ Repos wired:      %-43s║\n" "$repo_count"
    printf "║ Circle:           %-43s║\n" "$REPOWIRE_CIRCLE"
    printf "║ Timestamp:        %-43s║\n" "$TIMESTAMP"
    printf "╠══════════════════════════════════════════════════════════════════╣\n"
    printf "║ Artifacts                                                     ║\n"
    printf "╠══════════════════════════════════════════════════════════════════╣\n"
    printf "║ Peer defs:     ${STATE_DIR}/peers/║\n"
    printf "║ PR notifier:   ${REPOWIRE_DIR}/repowire-pr-notify.sh           ║\n"
    printf "║ Broadcast:     ${STATE_DIR}/hook-broadcast.sh                  ║\n"
    printf "║ Index:         ${STATE_DIR}/github-peers-index.yaml            ║\n"
    printf "║ CI template:   ${STATE_DIR}/workflow-templates/                ║\n"
    printf "║ Processed log: ${PROCESSED_LOG}                                ║\n"
    printf "║ Registered:    ${REGISTERED_LOG}                               ║\n"
    printf "╚══════════════════════════════════════════════════════════════════╝\n"

    printf "\n${BOLD}Peer identities created:${NC}\n"
    for ((i=0; i<${#REPO_LIST[@]}; i++)); do
        local peer_name
        peer_name="$(sanitize_peer_name "${REPO_LIST[$i]}")"
        printf "  ${GREEN}%-35s${NC} ↔ ${CYAN}%s/%s${NC}\n" "$peer_name" "${REPO_OWNER_LIST[$i]}" "${REPO_LIST[$i]}"
    done

    printf "\n${BOLD}Quick commands:${NC}\n"
    printf "  Watch PR events:  source ${REPOWIRE_DIR}/repowire-pr-notify.sh\n"
    printf "  Notify manually:  source ${REPOWIRE_DIR}/repowire-pr-notify.sh && repowire_pr_notify opened owner/repo \"PR title\" https://github.com/owner/repo/pull/1\n"
    printf "  CI integration:   cp ${STATE_DIR}/workflow-templates/repowire-notify.yml <repo>/.github/workflows/\n"
    printf "  Health check:     curl ${REPOWIRE_API}/health\n"
    printf "  List peers:       curl ${REPOWIRE_API}/peers\n"
    printf "  Register peer:    repowire peer register github-<repo-name> --circle ${REPOWIRE_CIRCLE}\n"
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    printf "${BOLD}${CYAN}"
    printf "╔══════════════════════════════════════════════════════════════════╗\n"
    printf "║     Wheeler GitHub-Repowire Agent Mesh Wiring                   ║\n"
    printf "║     v1.0.0 | Repowire %s | %s               ║\n" "$(curl -s "$REPOWIRE_API/health" --connect-timeout 3 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "?")" "$TIMESTAMP"
    printf "╚══════════════════════════════════════════════════════════════════╝\n"
    printf "${NC}\n"

    check_dependencies

    # Parse flags
    local skip_register=false
    local skip_hooks=false
    local skip_verify=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-register) skip_register=true ;;
            --skip-hooks) skip_hooks=true ;;
            --skip-verify) skip_verify=true ;;
            --circle) REPOWIRE_CIRCLE="$2"; shift ;;
            --org) WHEELER_ORG="$2"; shift ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --skip-register    Skip peer registration with daemon"
                echo "  --skip-hooks       Skip git post-commit hook installation"
                echo "  --skip-verify      Skip final mesh connectivity verification"
                echo "  --circle <name>    Set repowire circle (default: wheeler-github)"
                echo "  --org <name>       Set GitHub org name for repo discovery"
                echo "  --help             Show this help"
                exit 0
                ;;
            *) log_warn "Unknown option: $1 (use --help)" ;;
        esac
        shift
    done

    # Step 1: Discover repos
    discover_repos || true

    if [[ ${#REPO_LIST[@]} -eq 0 ]]; then
        log_error "No repos discovered. Cannot proceed."
        log_info "Try: WHEELER_REPO_NAMES='wheeler-brain-os wheeler-command-center' $0"
        log_info "Or:  gh auth login  # then re-run"
        log_info "Or:  export GITHUB_TOKEN=your_token  # then re-run"
        exit 1
    fi

    # Log processed repos
    for ((i=0; i<${#REPO_LIST[@]}; i++)); do
        echo "${REPO_OWNER_LIST[$i]}/${REPO_LIST[$i]}" >> "$PROCESSED_LOG"
    done
    sort -u "$PROCESSED_LOG" -o "$PROCESSED_LOG"

    # Step 3: Create peer definition YAML files
    create_repowire_peer_yaml

    # Step 4: Install post-commit hooks
    if [[ "$skip_hooks" != "true" ]]; then
        install_post_commit_hooks
    else
        log_info "Skipping post-commit hook installation (--skip-hooks)"
    fi

    # Step 5: Create PR notifier
    create_pr_notifier

    # Step 6: Create CI workflow template
    create_ci_workflow_template

    # Step 7: Register peers
    if [[ "$skip_register" != "true" ]]; then
        register_peers_with_daemon
    else
        log_info "Skipping peer registration (--skip-register)"
    fi

    # Step 8: Create consolidated index
    create_consolidated_peers_index

    # Step 9: Verify
    if [[ "$skip_verify" != "true" ]]; then
        verify_mesh || log_warn "Mesh verification had issues — see above."
    else
        log_info "Skipping verification (--skip-verify)"
    fi

    # Summary
    print_summary
}

main "$@"
