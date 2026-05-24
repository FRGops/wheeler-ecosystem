# PHASE-06: Risk Scoring

**Purpose:** Calculate a numeric deployment risk score (1-10) based on change size,
consumer blast radius, data layer impact, and architectural complexity.

**Prerequisites:** PHASE-03 dependency map, PHASE-04 architecture review, PHASE-05 security report.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

RISK_LOG="/var/log/wheeler/repo-router/risk/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${RISK_LOG}")"
exec > >(tee -a "${RISK_LOG}") 2>&1

echo "=== PHASE-06: Risk Scoring for ${SERVICE_NAME} ==="

# Initialize risk factors
RISK_CHANGE_SIZE=0      # 0-3
RISK_CONSUMERS=0        # 0-3
RISK_DATA=0             # 0-2
RISK_COMPLEXITY=0       # 0-2
TOTAL_RISK=0
```

## 2. Factor 1: Change Size (0-3)

```bash
echo ""
echo "=== Factor 1: Change Size ==="
cd "${REPO_PATH}"

if git rev-parse --git-dir >/dev/null 2>&1; then
    # Count changed files vs HEAD~5 (or all if shallow)
    COMMITS_BEHIND=$(git log --oneline HEAD..HEAD~5 2>/dev/null | wc -l || echo 0)
    FILES_CHANGED=$(git diff --name-only HEAD~5..HEAD 2>/dev/null | wc -l)
    LINES_CHANGED=$(git diff --stat HEAD~5..HEAD 2>/dev/null | tail -1 | grep -oP '\d+' | tail -1 || echo 0)

    echo "  Commits in window: ${COMMITS_BEHIND}"
    echo "  Files changed: ${FILES_CHANGED}"
    echo "  Lines changed: ${LINES_CHANGED}"

    if [[ "${FILES_CHANGED}" -le 2 && "${LINES_CHANGED}" -le 50 ]]; then
        RISK_CHANGE_SIZE=0
        echo "  [LOW] Minimal change (${FILES_CHANGED} files, ${LINES_CHANGED} lines)"
    elif [[ "${FILES_CHANGED}" -le 10 && "${LINES_CHANGED}" -le 300 ]]; then
        RISK_CHANGE_SIZE=1
        echo "  [MEDIUM] Moderate change (${FILES_CHANGED} files, ${LINES_CHANGED} lines)"
    elif [[ "${FILES_CHANGED}" -le 30 && "${LINES_CHANGED}" -le 1000 ]]; then
        RISK_CHANGE_SIZE=2
        echo "  [HIGH] Large change (${FILES_CHANGED} files, ${LINES_CHANGED} lines)"
    else
        RISK_CHANGE_SIZE=3
        echo "  [CRITICAL] Massive change (${FILES_CHANGED} files, ${LINES_CHANGED} lines)"
    fi
else
    echo "  [MEDIUM] No git history — treating as full deployment."
    RISK_CHANGE_SIZE=2
fi
```

## 3. Factor 2: Consumer Blast Radius (0-3)

```bash
echo ""
echo "=== Factor 2: Consumer Blast Radius ==="

# Count consumers found in dependency map
CONSUMER_FILE="/var/log/wheeler/repo-router/deps/${SERVICE_NAME}-deps.json"
CONSUMER_COUNT=0
if [[ -f "${CONSUMER_FILE}" ]]; then
    CONSUMER_COUNT=$(jq '.downstream_consumers | length' "${CONSUMER_FILE}" 2>/dev/null || echo 0)
fi

echo "  Known consumers: ${CONSUMER_COUNT}"

if [[ "${CONSUMER_COUNT}" -eq 0 ]]; then
    RISK_CONSUMERS=0
    echo "  [LOW] No downstream consumers identified."
elif [[ "${CONSUMER_COUNT}" -le 3 ]]; then
    RISK_CONSUMERS=1
    echo "  [MEDIUM] ${CONSUMER_COUNT} consumer(s) would be affected."
elif [[ "${CONSUMER_COUNT}" -le 10 ]]; then
    RISK_CONSUMERS=2
    echo "  [HIGH] ${CONSUMER_COUNT} consumers — moderate blast radius."
else
    RISK_CONSUMERS=3
    echo "  [CRITICAL] ${CONSUMER_COUNT} consumers — wide blast radius."
fi

# Check if this service is referenced by name in PM2/Docker across the fleet
echo "  Scanning for cross-service references..."
CROSS_REFS=$(grep -rl "${SERVICE_NAME}" /opt/wheeler/configs /root/infrastructure 2>/dev/null | \
  grep -v node_modules | grep -v '.git/' | wc -l)
echo "  Cross-service config references: ${CROSS_REFS}"
if [[ "${CROSS_REFS}" -gt 5 ]]; then
    RISK_CONSUMERS=$(( RISK_CONSUMERS + 1 > 3 ? 3 : RISK_CONSUMERS + 1 ))
    echo "  [INFO] Elevated risk due to cross-service config references."
fi
```

## 4. Factor 3: Data Layer Impact (0-2)

```bash
echo ""
echo "=== Factor 3: Data Layer Impact ==="

# Check for database-related changes
DATA_RISK=false
if git diff --name-only HEAD~5..HEAD 2>/dev/null | grep -qiE '\.sql$|schema|migration|prisma|sequelize|knex|alembic|django.db'; then
    DATA_RISK=true
    echo "  [DETECTED] Database schema/migration changes."
fi

if git diff HEAD~5..HEAD 2>/dev/null | grep -qE 'CREATE\s+TABLE|ALTER\s+TABLE|DROP\s+TABLE|migrate'; then
    DATA_RISK=true
    echo "  [DETECTED] DDL statements (CREATE/ALTER/DROP TABLE)."
fi

if [[ -d "${REPO_PATH}/migrations" || -d "${REPO_PATH}/prisma" ]]; then
    echo "  [DETECTED] Migration directory present."
fi

# Check Docker volumes for persistent data
if docker inspect "${SERVICE_NAME}" 2>/dev/null | jq -e '.[0].Mounts[] | select(.Type == "volume")' >/dev/null 2>&1; then
    echo "  [DETECTED] Docker volumes in use (persistent data)."
    DATA_RISK=true
fi

if [[ "${DATA_RISK}" == true ]]; then
    RISK_DATA=2
    echo "  [HIGH] Data layer changes detected — rollback may not fully revert state."
else
    RISK_DATA=0
    echo "  [LOW] No data layer changes detected."
fi
```

## 5. Factor 4: Architecture Complexity (0-2)

```bash
echo ""
echo "=== Factor 4: Architectural Complexity ==="

COMPLEXITY=0
# Docker + multiple services
if [[ -f "${REPO_PATH}/docker-compose.yml" ]]; then
    SERVICE_COUNT=$(grep -c '^\s' "${REPO_PATH}/docker-compose.yml" 2>/dev/null)
    if grep -q 'depends_on' docker-compose.yml 2>/dev/null; then
        COMPLEXITY=$((COMPLEXITY + 1))
        echo "  [DETECTED] Multi-service docker-compose with depends_on."
    fi
fi

# PM2 with cluster mode
if pm2 jlist 2>/dev/null | jq -e ".[] | select(.name == \"${SERVICE_NAME}\" and .pm2_env.exec_mode == \"cluster_mode\")" >/dev/null 2>&1; then
    COMPLEXITY=$((COMPLEXITY + 1))
    echo "  [DETECTED] PM2 cluster mode."
fi

# Reverse proxy dependencies
if docker inspect "${SERVICE_NAME}" 2>/dev/null | jq -e '.[0].Config.Labels | to_entries[] | select(.key | contains("traefik"))' >/dev/null 2>&1; then
    COMPLEXITY=$((COMPLEXITY + 1))
    echo "  [DETECTED] Traefik routing labels."
fi

RISK_COMPLEXITY=${COMPLEXITY}
echo "  Complexity score: ${COMPLEXITY}/2"
```

## 6. Calculate Total Risk Score

```bash
echo ""
echo "=== Final Risk Calculation ==="
echo "  Change Size:    ${RISK_CHANGE_SIZE}/3"
echo "  Consumer Blast: ${RISK_CONSUMERS}/3"
echo "  Data Impact:    ${RISK_DATA}/2"
echo "  Complexity:     ${RISK_COMPLEXITY}/2"

TOTAL_RISK=$(( RISK_CHANGE_SIZE + RISK_CONSUMERS + RISK_DATA + RISK_COMPLEXITY ))

# Normalize to 1-10 scale
if [[ "${TOTAL_RISK}" -le 2 ]]; then
    RISK_SCORE=1
    RISK_LABEL="TRIVIAL"
elif [[ "${TOTAL_RISK}" -le 4 ]]; then
    RISK_SCORE=3
    RISK_LABEL="LOW"
elif [[ "${TOTAL_RISK}" -le 6 ]]; then
    RISK_SCORE=5
    RISK_LABEL="MEDIUM"
elif [[ "${TOTAL_RISK}" -le 8 ]]; then
    RISK_SCORE=7
    RISK_LABEL="HIGH"
else
    RISK_SCORE=10
    RISK_LABEL="CRITICAL"
fi

echo ""
echo "  RISK SCORE: ${RISK_SCORE}/10 (${RISK_LABEL})"
echo "  Raw Total:  ${TOTAL_RISK}"
```

## 7. Write Risk Report & Enforce Gates

```bash
RISK_REPORT="/var/log/wheeler/repo-router/risk/${SERVICE_NAME}-risk.json"
cat > "${RISK_REPORT}" <<-EOF
{
  "service": "${SERVICE_NAME}",
  "risk_score": ${RISK_SCORE},
  "risk_label": "${RISK_LABEL}",
  "factors": {
    "change_size": ${RISK_CHANGE_SIZE},
    "blast_radius": ${RISK_CONSUMERS},
    "data_impact": ${RISK_DATA},
    "complexity": ${RISK_COMPLEXITY}
  },
  "total_raw": ${TOTAL_RISK},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo ""
echo "Risk report: ${RISK_REPORT}"

# Gate enforcement: block high/critical without approval
if [[ "${RISK_SCORE}" -ge 7 ]]; then
    echo ""
    echo "** GATE: Risk score >= 7 (${RISK_LABEL}). Manual approval required before deployment. **"
    echo "  Approval command:  echo 'approved' > /var/log/wheeler/repo-router/gate/${SERVICE_NAME}.approval"
    mkdir -p /var/log/wheeler/repo-router/gate/
    echo "pending" > "/var/log/wheeler/repo-router/gate/${SERVICE_NAME}.approval"
fi

echo ""
echo "PHASE-06 COMPLETE: ${SERVICE_NAME} risk scored at ${RISK_SCORE}/10 (${RISK_LABEL})"
```
