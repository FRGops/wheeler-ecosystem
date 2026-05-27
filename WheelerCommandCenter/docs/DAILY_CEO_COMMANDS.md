# Wheeler Daily CEO Commands

## Morning Routine (5 minutes)

```bash
# 1. Ecosystem health — are all servers alive?
wheeler health

# 2. Public domains — are customer-facing sites up?
wheeler domains

# 3. Smoke tests — are apps responding correctly?
wheeler smoke all

# 4. Daily briefing — what needs attention today?
wheeler today
```

## Weekly Routine

```bash
# Full system diagnostic
wheeler doctor

# Backup verification
wheeler backups

# Readiness scorecard
wheeler scorecard

# Repo check — any uncommitted work?
wheeler repos
```

## Before Deployment

```bash
wheeler repos                         # Check repo state
wheeler deploy <app> --dry-run        # Preflight
wheeler smoke <app>                   # Current version healthy?
wheeler backups                       # Backup current?
wheeler deploy <app> --execute        # Deploy (intentional)
wheeler smoke <app>                   # Verify new version
```

## Emergency (anytime)

```bash
wheeler panic           # Instant triage
wheeler logs <service>  # Investigate
wheeler docker all      # Container status
```

## Quick Aliases

If shell integration is installed:
```bash
wh     → wheeler
whh    → wheeler health
whp    → wheeler panic
whd    → wheeler domains
whs    → wheeler smoke all
whm    → wheeler mesh
```

## AI Model Management

```bash
wheeler ai status     # Which AI backend is active?
wheeler ai claude     # Switch to Claude
wheeler ai deepseek   # Switch to DeepSeek
wheeler ai reset      # Clear everything
```

## Agent Fleet

```bash
wheeler agents list    # Show all agents
wheeler agents status  # Agent fleet status
```

## Health Score Tracking

```bash
wheeler scorecard      # Current readiness score
# Scorecards saved to ~/WheelerCommandCenter/scorecards/
```
