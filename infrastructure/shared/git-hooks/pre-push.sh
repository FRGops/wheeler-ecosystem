#!/usr/bin/env bash
# ==============================================================================
# pre-push.sh — Git pre-push hook for developers
# ==============================================================================
#
# Installed in .git/hooks/pre-push on developer workstations.
# Runs before every `git push` to catch issues early.
#
# Checks:
#   1. Linting passes (language-appropriate)
#   2. Unit tests pass
#   3. No hardcoded secrets or credentials
#   4. Docker compose files have valid syntax
#   5. No direct pushes to protected branches (main, production)
#
# Installation:
#   ln -sf ../../shared/git-hooks/pre-push.sh .git/hooks/pre-push
#   # OR for a single project:
#   cp shared/git-hooks/pre-push.sh /path/to/project/.git/hooks/pre-push
#
# Configuration (via git config):
#   git config hooks.pre-push.allow-main false   # Block pushes to main
#   git config hooks.pre-push.skip-lint false     # Skip lint check
#   git config hooks.pre-push.skip-secrets false  # Skip secrets check
#   git config hooks.pre-push.skip-docker false   # Skip docker compose check
#
# Skip all checks (emergency use only):
#   git push --no-verify
#   # OR: export SKIP_PRE_PUSH=true && git push
# ==============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
ALLOW_MAIN=$(git config --bool hooks.pre-push.allow-main 2>/dev/null || echo "false")
SKIP_LINT=$(git config --bool hooks.pre-push.skip-lint 2>/dev/null || echo "false")
SKIP_SECRETS=$(git config --bool hooks.pre-push.skip-secrets 2>/dev/null || echo "false")
SKIP_DOCKER=$(git config --bool hooks.pre-push.skip-docker 2>/dev/null || echo "false")

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
banner()  { echo -e "${CYAN}$*${NC}"; }

# --- Parse pre-push input ----------------------------------------------------
# Git pre-push hook receives on stdin: "<local-ref> <local-sha> <remote-ref> <remote-sha>"
parse_input() {
    local input
    input=$(cat)
    if [[ -z "$input" ]]; then
        return 1
    fi

    # Parse the push target
    local remote_ref
    remote_ref=$(echo "$input" | awk '{print $2}')
    echo "$remote_ref"
}

# --- Check for protected branches --------------------------------------------
check_protected_branches() {
    local remote_ref="$1"

    # Extract branch name from ref (refs/heads/<branch>)
    local branch
    branch=$(echo "$remote_ref" | sed 's|refs/heads/||')

    if [[ "$branch" == "main" ]] && [[ "$ALLOW_MAIN" != "true" ]]; then
        # Check if it's a forced push or direct push
        error "=============================================="
        error "  PUSH TO MAIN BLOCKED"
        error "=============================================="
        echo ""
        error "Direct pushes to the 'main' branch are not allowed."
        error ""
        error "  Instead:"
        error "    1. Create a feature branch: git checkout -b feat/my-feature"
        error "    2. Push the feature branch: git push origin feat/my-feature"
        error "    3. Open a pull request on GitHub"
        error ""
        error "  To bypass (not recommended):"
        error "    git push --no-verify"
        error ""
        error "  To allow main pushes (team lead):"
        error "    git config hooks.pre-push.allow-main true"
        echo ""
        return 1
    fi

    if [[ "$branch" == "production" ]] || [[ "$branch" == "master" ]]; then
        error "=============================================="
        error "  PUSH TO PROTECTED BRANCH BLOCKED"
        error "=============================================="
        echo ""
        error "Direct pushes to '${branch}' are not allowed."
        error "Please use a pull request."
        echo ""
        return 1
    fi

    if [[ "$branch" == "staging" ]] || [[ "$branch" == "develop" ]]; then
        warn "Pushing to '${branch}' — make sure CI will run."
    fi

    return 0
}

# --- Run linting -------------------------------------------------------------
run_lint() {
    if [[ "$SKIP_LINT" == "true" ]]; then
        info "[SKIP] Linting (disabled by config)"
        return 0
    fi

    info "Running linting checks..."

    # Detect language and run appropriate linter
    local has_failure=false

    if [[ -f "package.json" ]]; then
        if command -v npm &>/dev/null; then
            if npm run lint 2>/dev/null; then
                success "ESLint passed"
            else
                # Check if the lint script exists
                if grep -q '"lint"' package.json 2>/dev/null; then
                    error "ESLint found issues"
                    has_failure=true
                else
                    info "No lint script in package.json, skipping"
                fi
            fi
        fi
    fi

    if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
        if command -v ruff &>/dev/null; then
            if ruff check . 2>/dev/null; then
                success "Ruff (Python linter) passed"
            else
                error "Ruff found issues"
                has_failure=true
            fi
        elif command -v pylint &>/dev/null; then
            if pylint --exit-zero **/*.py 2>/dev/null; then
                success "Pylint passed"
            else
                warn "Pylint found issues (non-blocking)"
            fi
        elif command -v flake8 &>/dev/null; then
            if flake8 . 2>/dev/null; then
                success "Flake8 passed"
            else
                error "Flake8 found issues"
                has_failure=true
            fi
        else
            info "No Python linter installed (ruff/pylint/flake8), skipping"
        fi
    fi

    # ShellCheck any shell scripts
    if find . -name "*.sh" -not -path "./.git/*" | head -1 &>/dev/null; then
        if command -v shellcheck &>/dev/null; then
            local shell_issues
            shell_issues=$(find . -name "*.sh" -not -path "./.git/*" -exec shellcheck -s bash {} \; 2>&1 | grep -c "^In " || true)
            if [[ "$shell_issues" -gt 0 ]]; then
                warn "ShellCheck found ${shell_issues} issue(s) — review recommended"
            else
                success "ShellCheck passed"
            fi
        fi
    fi

    if [[ -f "Dockerfile" ]]; then
        if command -v hadolint &>/dev/null; then
            if hadolint Dockerfile 2>/dev/null; then
                success "Hadolint (Dockerfile) passed"
            else
                warn "Hadolint found issues"
            fi
        fi
    fi

    if [[ "$has_failure" == "true" ]]; then
        return 1
    fi

    return 0
}

# --- Run tests ---------------------------------------------------------------
run_tests() {
    info "Running tests..."

    local has_tests=false
    local has_failure=false

    if [[ -f "package.json" ]]; then
        if grep -q '"test"' package.json 2>/dev/null; then
            has_tests=true
            info "Running: npm test"
            if npm test 2>&1 | tail -20; then
                success "JavaScript tests passed"
            else
                error "JavaScript tests failed"
                has_failure=true
            fi
        fi
    fi

    if [[ -f "Makefile" ]]; then
        if grep -q '^test:' Makefile 2>/dev/null; then
            has_tests=true
            info "Running: make test"
            if make test 2>&1 | tail -20; then
                success "Make tests passed"
            else
                error "Make tests failed"
                has_failure=true
            fi
        fi
    fi

    if [[ -f "pyproject.toml" ]]; then
        if command -v pytest &>/dev/null; then
            has_tests=true
            info "Running: pytest"
            if python -m pytest -x -q --tb=short 2>&1 | tail -20; then
                success "Python tests passed"
            else
                error "Python tests failed"
                has_failure=true
            fi
        fi
    fi

    if [[ "$has_tests" == "false" ]]; then
        info "No test runner detected (npm test, make test, pytest), skipping"
    fi

    if [[ "$has_failure" == "true" ]]; then
        return 1
    fi

    return 0
}

# --- Check for secrets in code -----------------------------------------------
check_secrets() {
    if [[ "$SKIP_SECRETS" == "true" ]]; then
        info "[SKIP] Secrets check (disabled by config)"
        return 0
    fi

    info "Checking for hardcoded secrets..."

    # Patterns that indicate secrets might be hardcoded
    local patterns=(
        'AKIA[0-9A-Z]{16}'                           # AWS Access Key
        'sk-[A-Za-z0-9]{32,}'                        # OpenAI/Anthropic API key
        'sk-ant-[A-Za-z0-9]{32,}'                    # Anthropic API key
        'ghp_[A-Za-z0-9]{36,}'                       # GitHub PAT
        'gho_[A-Za-z0-9]{36,}'                       # GitHub OAuth
        'xox[bpsa]-[A-Za-z0-9-]{10,}'                # Slack tokens
        '-----BEGIN (RSA |EC )?PRIVATE KEY-----'     # Private keys
        'password\s*=\s*['"'"'"]'                     # Hardcoded passwords
        'PASSWORD\s*=\s*['"'"'"]'
        'secret\s*=\s*['"'"'"]'
        'api_key\s*=\s*['"'"'"]'
        'apiKey\s*=\s*['"'"'"]'
    )

    local found_issues=0
    local tmpfile
    tmpfile=$(mktemp)

    for pattern in "${patterns[@]}"; do
        # Search staged changes if possible, otherwise search the working directory
        if git rev-parse --git-dir &>/dev/null; then
            # Check staged changes (what's about to be pushed)
            git diff --cached -G "$pattern" -- ':!.git/hooks/*' ':!.env*' ':!*.env.*' ':!**/.env' ':!*secrets*' 2>/dev/null | grep -E "$pattern" > "$tmpfile" || true
        else
            # Fallback: check working tree
            grep -rn --include="*.py" --include="*.js" --include="*.ts" --include="*.yml" --include="*.yaml" \
                --include="*.json" --include="*.sh" --include="*.tf" \
                --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv \
                --exclude-dir=vendor --exclude-dir=__pycache__ \
                -E "$pattern" . 2>/dev/null > "$tmpfile" || true
        fi

        if [[ -s "$tmpfile" ]]; then
            error "Potential secret found matching pattern: ${pattern}"
            while IFS= read -r line; do
                warn "  ${line}"
            done < "$tmpfile"
            found_issues=$((found_issues + 1))
        fi
    done

    rm -f "$tmpfile"

    if [[ $found_issues -gt 0 ]]; then
        error "${found_issues} potential secret(s) found!"
        error ""
        error "  Remove secrets from code and use environment variables instead."
        error "  Add secrets to /opt/wheeler/config/envs/<app>.env on the server."
        error ""
        error "  To skip this check (emergency): git push --no-verify"
        return 1
    fi

    # Check for .env files being committed
    if git rev-parse --git-dir &>/dev/null; then
        local env_staged
        env_staged=$(git diff --cached --name-only | grep -E '\.env$' | grep -v '.env.example' || true)
        if [[ -n "$env_staged" ]]; then
            warn ".env files are staged for commit:"
            echo "$env_staged" | while IFS= read -r line; do
                warn "  ${line}"
            done
            warn "Are you sure you want to commit environment files?"
            warn "They often contain secrets. Use .env.example instead."
            # Non-blocking warning
        fi
    fi

    success "Secrets check passed"
    return 0
}

# --- Validate docker-compose syntax ------------------------------------------
check_docker_compose() {
    if [[ "$SKIP_DOCKER" == "true" ]]; then
        info "[SKIP] Docker Compose validation (disabled by config)"
        return 0
    fi

    info "Validating Docker Compose files..."

    local has_failure=false

    # Check for compose files in the changes
    local compose_files
    compose_files=$(git diff --cached --name-only 2>/dev/null | grep -E 'docker-compose.*\.yml' || true)

    if [[ -z "$compose_files" ]]; then
        compose_files=$(find . -name "docker-compose*.yml" -not -path "./.git/*" 2>/dev/null)
    fi

    for file in $compose_files; do
        if [[ -f "$file" ]]; then
            if command -v docker &>/dev/null; then
                if docker compose -f "$file" config -q 2>/dev/null; then
                    success "  ${file}: valid syntax"
                else
                    error "  ${file}: INVALID SYNTAX"
                    docker compose -f "$file" config 2>&1 | head -10 || true
                    has_failure=true
                fi
            else
                # Basic YAML check (less thorough but no Docker needed)
                if command -v python3 &>/dev/null; then
                    python3 -c "
import yaml, sys
try:
    with open('${file}') as f:
        yaml.safe_load(f)
    sys.exit(0)
except Exception as e:
    print(str(e))
    sys.exit(1)
" 2>/dev/null || {
                        warn "  ${file}: could not validate (install Docker or PyYAML)"
                    }
                fi
            fi
        fi
    done

    if [[ "$has_failure" == "true" ]]; then
        return 1
    fi

    return 0
}

# --- Print pre-push summary --------------------------------------------------
print_summary() {
    echo ""
    echo "=============================================="
    echo "  PRE-PUSH CHECKS SUMMARY"
    echo "=============================================="
    echo ""

    if [[ $1 -eq 0 ]]; then
        success "All checks passed! Push proceeding..."
        echo ""
        banner "  ✓ Linting"
        banner "  ✓ Tests"
        banner "  ✓ Secrets scan"
        banner "  ✓ Docker Compose validation"
    else
        error "Some checks failed. Push blocked."
        echo ""
        error "  Fix the issues above or use git push --no-verify"
        error "  (--no-verify should only be used in emergencies)"
    fi
}

# --- Main --------------------------------------------------------------------
main() {
    local remote_ref
    remote_ref=$(parse_input) || remote_ref="unknown"

    echo ""
    echo "=============================================="
    echo "  PRE-PUSH HOOK"
    echo "  Remote ref: ${remote_ref}"
    echo "  Timestamp:  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "=============================================="
    echo ""

    # Allow override for emergency pushes
    if [[ "${SKIP_PRE_PUSH:-}" == "true" ]]; then
        warn "SKIP_PRE_PUSH is set — bypassing all checks"
        exit 0
    fi

    # Check for uncommitted changes warning
    if ! git diff --quiet --exit-code 2>/dev/null; then
        warn "You have uncommitted changes. Consider committing them before pushing."
    fi

    local exit_code=0

    # 1. Protected branch check
    if ! check_protected_branches "$remote_ref"; then
        exit_code=1
    fi

    # 2. Linting
    if ! run_lint; then
        exit_code=1
    fi

    # 3. Tests
    if ! run_tests; then
        exit_code=1
    fi

    # 4. Secrets check
    if ! check_secrets; then
        exit_code=1
    fi

    # 5. Docker compose
    if ! check_docker_compose; then
        exit_code=1
    fi

    print_summary $exit_code

    exit $exit_code
}

main "$@"
