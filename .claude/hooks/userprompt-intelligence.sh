#!/bin/bash
# Wheeler Coding OS — UserPromptSubmit Intelligence Hook v2.2
# Dynamic keyword-to-domain matching. New agents/skills/plugins auto-discover.
# No hardcoded agent names — uses domain recommendations the model resolves.
set -e

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || echo "")

if [ -z "$PROMPT" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":""}}'
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# DYNAMIC DOMAIN MATCHER — Add domains here, agents auto-match
# Format: "domain:keyword1|keyword2|keyword3"
# New agents matching these keywords → auto-recommended. Zero config.
# ═══════════════════════════════════════════════════════════════

matched_domains() {
    local prompt="$1"
    local domains=(
        "backend-api:api|endpoint|rest|graphql|route|controller|middleware|fastapi|express|django|server"
        "frontend-ui:ui|component|react|vue|angular|css|tailwind|layout|button|form|modal|page|frontend"
        "database:database|sql|postgres|prisma|schema|migration|query|index|table|column|redis"
        "devops:docker|container|compose|kubernetes|k8s|deploy|ci/cd|pipeline|build|image|port"
        "testing:test|spec|jest|pytest|coverage|mock|stub|assert|e2e|integration|unit.test"
        "security:security|secret|token|vulnerability|owasp|cve|ssl|tls|injection|xss|auth|breach"
        "review:review|audit|check|quality|lint|code.quality|inspect"
        "performance:performance|optimize|slow|fast|memory|cpu|latency|cache|speed|perf"
        "architecture:architecture|design|pattern|structure|system|refactor|module|system.design"
        "observability:log|monitor|alert|metric|dashboard|health|check|prometheus|grafana|loki"
        "documentation:docs|document|readme|comment|docstring|wiki|documentation"
        "cli-tool:cli|script|bash|shell|command|tool|utility|automation"
        "pm2-ecosystem:pm2|process|restart|crashed|jlist|daemon|save|resurrect"
        "docker-ecosystem:docker|container|health|image|port|compose|registry"
        "github:github|pr|pull.request|issue|commit|push|repo|git"
        "infrastructure:infrastructure|server|network|ufw|nginx|proxy|gateway|dns|cert"
        "financial:revenue|cost|mrr|arr|stripe|billing|invoice|payment|pricing"
        "ai-llm:llm|model|routing|deepseek|claude|openai|token|embedding|rag|vector"
        "agent-sdk:sdk|agent.sdk|anthropic|claude.api|managed.agent"
        "multi-agent:agent|orchestrate|coordinate|fleet|army|parallel|multi.agent|pipeline"
        "deploy:deploy|release|ship|production|publish|rollback|launch"
        "config:config|settings|env|environment|variable|hook|permission|allow"
    )

    local matched=""
    for domain in "${domains[@]}"; do
        local name="${domain%%:*}"
        local keywords="${domain#*:}"
        if echo "$prompt" | grep -qiE "($keywords)"; then
            matched="$matched $name"
        fi
    done
    echo "$matched" | xargs 2>/dev/null || true
}

MATCHED_DOMAINS=$(matched_domains "$PROMPT")

# ═══════════════════════════════════════════════════
# TASK TYPE CLASSIFICATION
# ═══════════════════════════════════════════════════
TASK_TYPE="unknown"
if echo "$PROMPT" | grep -qiE '\b(fix|bug|broken|crash|error|issue|repair|debug)\b'; then
    TASK_TYPE="bug-fix"
elif echo "$PROMPT" | grep -qiE '\b(add|create|build|implement|new.feature|develop|make|generate|write)\b'; then
    TASK_TYPE="feature"
elif echo "$PROMPT" | grep -qiE '\b(refactor|clean.up|simplif|reorgani|restructur|improve)\b'; then
    TASK_TYPE="refactor"
elif echo "$PROMPT" | grep -qiE '\b(optimiz|faster|slow|performance|speed|perf)\b'; then
    TASK_TYPE="optimization"
elif echo "$PROMPT" | grep -qiE '\b(investigate|explore|understand|what|how|why|research|audit|scan)\b'; then
    TASK_TYPE="investigation"
elif echo "$PROMPT" | grep -qiE '\b(deploy|release|ship|production|publish)\b'; then
    TASK_TYPE="deploy"
fi

# ═══════════════════════════════════════════════════
# TASK SIZE ESTIMATION (v2.2 — always-on army enforcement, no suppression)
# ═══════════════════════════════════════════════════
TASK_SIZE="medium"
PROMPT_LEN=$(echo "$PROMPT" | wc -c)
if echo "$PROMPT" | grep -qiE '\b(tiny|minor|quick|single|one.line|one.file|typo|spelling|trivial|simple|just|only|small|nano)\b'; then
    TASK_SIZE="micro"
# Auto-classify short prompts (≤80 chars) as micro UNLESS they contain multi/army/everything keywords
elif [ "$PROMPT_LEN" -le 80 ] && ! echo "$PROMPT" | grep -qiE '\b(multi|many|all|every|entire|full|system|army|everything)\b'; then
    TASK_SIZE="micro"
elif echo "$PROMPT" | grep -qiE '\b(medium|several|multiple|feature|module)\b'; then
    TASK_SIZE="medium"
elif echo "$PROMPT" | grep -qiE '\b(large|major|big|complex|system|platform|full|entire|complete|army|many|all|everything)\b'; then
    TASK_SIZE="large"
elif echo "$PROMPT" | grep -qiE '\b(production|critical|urgent|security|breach|incident|emergency)\b'; then
    TASK_SIZE="critical"
fi

# ═══════════════════════════════════════════════════
# BUILD INTENT + ARMY MODE
# ═══════════════════════════════════════════════════
BUILD_INTENT="no"
if echo "$PROMPT" | grep -qiE '\b(build|code|implement|create|develop|make|write|add|fix|refactor|deploy|generate)\b'; then
    BUILD_INTENT="yes"
fi

# ═══════════════════════════════════════════════════════════════
# ARMY MODE — ALWAYS ON for Wheeler Coding OS v2.2
# NON-NEGOTIABLE: Every prompt deploys agents. Minimum 2 agents always.
# The model MUST call Agent() at least once. Suppression is forbidden.
# ═══════════════════════════════════════════════════════════════
ARMY_MODE="yes"
case "$TASK_SIZE" in
    micro|small)
        ARMY_DEPLOY_COUNT="2 (MINIMUM — NEVER less than 2)"
        ;;
    medium)
        ARMY_DEPLOY_COUNT="4"
        ;;
    large)
        ARMY_DEPLOY_COUNT="6"
        ;;
    critical)
        ARMY_DEPLOY_COUNT="as-needed"
        ;;
esac

# ═══════════════════════════════════════════════════
# PIPELINE DEPTH + REVIEW LEVEL
# ═══════════════════════════════════════════════════
case "$TASK_SIZE" in
    micro)   PIPELINE_DEPTH="2-phases (IMPLEMENT→REVIEW)" ; REVIEW_LEVEL="Self" ;;
    small)   PIPELINE_DEPTH="4-phases (PLAN→IMPLEMENT→TEST→REVIEW)" ; REVIEW_LEVEL="Peer" ;;
    medium)  PIPELINE_DEPTH="6-phases (DISCOVER→PLAN→IMPLEMENT→TEST→REVIEW→SECURITY→FINAL)" ; REVIEW_LEVEL="Final Boss" ;;
    large)   PIPELINE_DEPTH="7-phases (full pipeline)" ; REVIEW_LEVEL="Final Boss + Human" ;;
    critical) PIPELINE_DEPTH="7-phases + human gates" ; REVIEW_LEVEL="Final Boss + Human" ;;
esac

# ═══════════════════════════════════════════════════
# HUMAN GATE CHECK
# ═══════════════════════════════════════════════════
NEEDS_HUMAN="no"
if echo "$PROMPT" | grep -qiE '\b(production.deploy|db.migration|secret|\.env|shell.profile|deepseek.routing|auth.change|security.change|payment)\b'; then
    NEEDS_HUMAN="yes"
fi

# ═══════════════════════════════════════════════════
# ARMY ALWAYS-ON (v2.2) — NO SUPPRESSION. ALL PROMPTS GET FULL ARMY CONTEXT.
# Every prompt deploys agents. No exceptions. No opt-out. No suppression.
# ═══════════════════════════════════════════════════

# ═══════════════════════════════════════════════════
# BUILD CONTEXT WITH DYNAMIC AGENT/SKILL RECOMMENDATIONS
# ═══════════════════════════════════════════════════

# Build domain-specific agent deployment recommendations
DOMAIN_DEPLOY=""
if [ -n "$MATCHED_DOMAINS" ]; then
    DOMAIN_DEPLOY="

🔍 AUTO-DETECTED CAPABILITY DOMAINS: $MATCHED_DOMAINS
  → MUST deploy agents from these domains (use Agent tool's subagent_type list) — NON-NEGOTIABLE
  → Agent names matching these domains auto-qualify — new agents auto-participate
  → Match domain keywords to available subagent_type values
  → ⛔ SKIPPING agents = POLICY VIOLATION — deploy minimum 2 agents on EVERY prompt"
fi

# Build auto-skill recommendations from matched domains
SKILL_RECS=""
for d in $MATCHED_DOMAINS; do
    case "$d" in
        pm2-ecosystem) SKILL_RECS="$SKILL_RECS /slay" ;;
        config)        SKILL_RECS="$SKILL_RECS /update-config" ;;
        multi-agent)   SKILL_RECS="$SKILL_RECS /superpowers" ;;
        docker-ecosystem) SKILL_RECS="$SKILL_RECS /docker-health" ;;
        security)      SKILL_RECS="$SKILL_RECS /secrets-scan" ;;
        deploy)        SKILL_RECS="$SKILL_RECS /deploy-safety" ;;
        infrastructure) SKILL_RECS="$SKILL_RECS /tcp-gate" ;;
        financial)     SKILL_RECS="$SKILL_RECS /financial-health" ;;
        review)        SKILL_RECS="$SKILL_RECS /code-review" ;;
    esac
done

SKILL_RECS=$(echo "$SKILL_RECS" | xargs 2>/dev/null || true)

# ═══════════════════════════════════════════════════
# DISCOVERY CACHE (v2.2 — skip redundant codebase scans)
# ═══════════════════════════════════════════════════
DISCOVERY_CACHE_DIR="${HOME}/.ai/discover-cache"
mkdir -p "$DISCOVERY_CACHE_DIR" 2>/dev/null || true
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "no-git")
FILE_HASH=$(git ls-files 2>/dev/null | md5sum | cut -d' ' -f1 || echo "no-hash")
DISCOVERY_CACHE_FILE="${DISCOVERY_CACHE_DIR}/discover-${GIT_HEAD}-${FILE_HASH}.json"
DISCOVERY_CACHED="no"
DISCOVERY_CACHE_AGE_MAX=3600  # 1 hour TTL
CACHED_DISCOVER_CONTEXT=""

if [ "$TASK_SIZE" = "medium" ] || [ "$TASK_SIZE" = "large" ]; then
    if [ -f "$DISCOVERY_CACHE_FILE" ]; then
        CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$DISCOVERY_CACHE_FILE" 2>/dev/null || echo 0)))
        if [ "$CACHE_AGE" -lt "$DISCOVERY_CACHE_AGE_MAX" ]; then
            DISCOVERY_CACHED="yes"
            CACHED_DISCOVER_CONTEXT=$(cat "$DISCOVERY_CACHE_FILE" | jq -c '.summary // ""' 2>/dev/null || echo "")
        fi
    fi
fi

# ═══════════════════════════════════════════════════
# MODEL ROUTING HINTS (v2.1 — faster models for simple agents)
# ═══════════════════════════════════════════════════
case "$TASK_SIZE" in
    micro|small)
        MODEL_HINT="Use deepseek-chat for all agents (speed-critical, simple task)"
        ;;
    medium|large)
        MODEL_HINT="IMPLEMENT/DISCOVER agents: deepseek-chat (speed). REVIEW/SECURITY: claude-sonnet-4 or premium_review (quality). FINAL BOSS: claude-opus-4."
        ;;
    critical)
        MODEL_HINT="DISCOVER/IMPLEMENT: deepseek-chat. REVIEW/SECURITY: claude-sonnet-4. FINAL BOSS: claude-opus-4. Human gates active."
        ;;
esac

BUILD_CONTEXT="

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 WHEELER CODING OS v2.2 | $TASK_TYPE | $TASK_SIZE
Army: $ARMY_MODE (MANDATORY) | Agents: ${ARMY_DEPLOY_COUNT:-varies} | Phases: 7
Review: $REVIEW_LEVEL | Human: $NEEDS_HUMAN | Auto-Approve: YES
Model: ${MODEL_HINT}
⛔ ARMY DEPLOYMENT IS NON-NEGOTIABLE — Agent() tool call REQUIRED on every prompt
✅ AUTO-APPROVE LOCKED — Never call EnterPlanMode/ExitPlanMode/AskUserQuestion. Just build.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$DOMAIN_DEPLOY
"

# ── Discovery Cache ──
if [ "$DISCOVERY_CACHED" = "yes" ]; then
    BUILD_CONTEXT="$BUILD_CONTEXT
📦 DISCOVERY CACHED ($(printf '%d' "$CACHE_AGE")s, $(git rev-parse --short HEAD 2>/dev/null || echo '?')) — skip DISCOVER unless touching uncached areas.
"
fi

# ── Compact rules (token-optimized) ──
BUILD_CONTEXT="$BUILD_CONTEXT
Pipeline: .ai/subagents/BUILD_PIPELINE.md | Matrix: .ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md
Rules: REVIEW+SECURITY parallel. VERIFY+FINAL parallel. Handoff each phase. No 2 agents on same file. Evidence only — no false greens.
"

# ── Army Mode (ALWAYS ON — v2.2) ──
BUILD_CONTEXT="$BUILD_CONTEXT
⚔️ ARMY DEPLOY (${ARMY_DEPLOY_COUNT}): MANDATORY agent deployment on EVERY prompt. Use Agent tool AT LEAST ONCE per response. Parallel agents in single message with explicit file boundaries. agent-coordination for dedup. NO EXCEPTIONS. NO SKIPPING. NON-NEGOTIABLE.
"

# ── Walk-Away + Never-Stop ──
BUILD_CONTEXT="$BUILD_CONTEXT
🚀 WALK-AWAY + ⛔ NEVER-STOP + ✅ AUTO-APPROVE: auto-progress all phases, never wait for human, never call EnterPlanMode/ExitPlanMode. Time budgets per phase. 3x loop→alt approach. 5x→escalate. Must end: 100/100, UNVERIFIED list, or blocker report.
"

# ── Human Gate ──
if [ "$NEEDS_HUMAN" = "yes" ]; then
    BUILD_CONTEXT="$BUILD_CONTEXT

⚠️ HUMAN APPROVAL REQUIRED — pause and request before proceeding
"
fi

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":$(echo "$BUILD_CONTEXT" | jq -Rs .)}}"
