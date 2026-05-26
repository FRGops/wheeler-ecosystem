# Wheeler AI Coding OS — Index

## Policies
- [DeepSeek V4 Primary Policy](model-routing/DEEPSEEK_V4_PRIMARY_POLICY.md) — DO NOT TOUCH
- [Model Routing Decision Matrix](model-routing/MODEL_ROUTING_DECISION_MATRIX.md) — Which model for which task
- [Escalation Policy](model-routing/ESCALATION_POLICY.md) — When to escalate and to whom

## Subagents
- [Agent Army Deployment Matrix](subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md) — When to deploy which agents
- [Orchestrator Agent](subagents/ORCHESTRATOR_AGENT.md)
- [DeepSeek Implementer Agent](subagents/DEEPSEEK_IMPLEMENTER_AGENT.md)
- [Backend API Agent](subagents/BACKEND_API_AGENT.md)
- [Frontend UI Agent](subagents/FRONTEND_UI_AGENT.md)
- [Test QA Agent](subagents/TEST_QA_AGENT.md)
- [DevOps Safety Agent](subagents/DEVOPS_SAFETY_AGENT.md)
- [Security Secrets Agent](subagents/SECURITY_SECRETS_AGENT.md)
- [Database Agent](subagents/DATABASE_AGENT.md)
- [Docs Playbook Agent](subagents/DOCS_PLAYBOOK_AGENT.md)
- [Final Boss Reviewer Agent](subagents/FINAL_BOSS_REVIEWER_AGENT.md)
- [Dependency Risk Agent](subagents/DEPENDENCY_RISK_AGENT.md)
- [Observability Agent](subagents/OBSERVABILITY_AGENT.md)
- [Performance Agent](subagents/PERFORMANCE_AGENT.md)
- [Accessibility Agent](subagents/ACCESSIBILITY_AGENT.md)
- [SEO Conversion Agent](subagents/SEO_CONVERSION_AGENT.md)

## Autonomy
- [Preflight Checklist](autonomy/PREFLIGHT_CHECKLIST.md)
- [Postflight Checklist](autonomy/POSTFLIGHT_CHECKLIST.md)
- [Army Mode Policy](autonomy/ARMY_MODE_POLICY.md)
- [Autonomy Levels](autonomy/AUTONOMY_LEVELS.md)
- [Human Approval Gates](autonomy/HUMAN_APPROVAL_GATES.md)

## Session Launchers
- [Preflight Script](session-launchers/preflight-ai-session.sh)
- [Postflight Script](session-launchers/postflight-ai-session.sh)
- [Session Summarizer](session-launchers/summarize-ai-sessions.sh)
- [Auto Bootstrap](session-launchers/auto-session-bootstrap.sh)
- [Start Next Safe Session](session-launchers/start-next-safe-ai-session.sh)
- [Start AI Mission](session-launchers/start-ai-mission.sh)

## Hooks
- [SessionStart Bootstrap](.claude/hooks/sessionstart-autobootstrap.sh)
- [PreToolUse Safety](.claude/hooks/pretooluse-safety.sh)
- [PostToolUse Log](.claude/hooks/posttooluse-log.sh)
- [Stop Postflight](.claude/hooks/stop-postflight.sh)
- [Hooks Install & Rollback](claude/HOOKS_INSTALL_AND_ROLLBACK.md)
- [Project Hooks Template](claude/PROJECT_HOOKS_TEMPLATE_SETTINGS.json)

## CI/CD
- [CI Security Hardening Plan](ci/CI_SECURITY_HARDENING_PLAN.md)
- [AI Quality Gates](../../.github/workflows/ai-quality-gates.yml)
- [Secret Safety Scan](../../.github/workflows/secret-safety.yml)
- [Dependency Review](../../.github/workflows/dependency-review.yml)

## MCP Governance
- [MCP Governance Policy](mcp/MCP_GOVERNANCE_POLICY.md)
- [MCP Server Allowlist](mcp/MCP_SERVER_ALLOWLIST.md)
- [MCP Server Denylist](mcp/MCP_SERVER_DENYLIST.md)

## Skills
- [Agent Skills Registry](skills/AGENT_SKILLS_REGISTRY.md)
- [Skill Creation Template](skills/SKILL_CREATION_TEMPLATE.md)

## Observability
- [AI Session Telemetry](observability/AI_SESSION_TELEMETRY.md)
- [Agent Activity Log Schema](observability/AGENT_ACTIVITY_LOG_SCHEMA.md)
- [Readiness Score Schema](observability/READINESS_SCORE_SCHEMA.md)

## Evals
- [AI Output Eval Rubric](evals/AI_OUTPUT_EVAL_RUBRIC.md)
- [Code Quality Rubric](evals/CODE_QUALITY_RUBRIC.md)
- [Final Boss Acceptance Rubric](evals/FINAL_BOSS_ACCEPTANCE_RUBRIC.md)
- [Bug Regression Rubric](evals/BUG_REGRESSION_RUBRIC.md)
- [UI/UX Acceptance Rubric](evals/UI_UX_ACCEPTANCE_RUBRIC.md)
- [API Acceptance Rubric](evals/API_ACCEPTANCE_RUBRIC.md)
- [DevOps Acceptance Rubric](evals/DEVOPS_ACCEPTANCE_RUBRIC.md)

## Runbooks
- [Rollback Runbook](runbooks/ROLLBACK_RUNBOOK.md)
- [AI Session Recovery](runbooks/AI_SESSION_RECOVERY_RUNBOOK.md)
- [Broken DeepSeek Routing — DO NOT TOUCH](runbooks/BROKEN_DEEPSEEK_ROUTING_DO_NOT_TOUCH_RUNBOOK.md)
- [Broken Build](runbooks/BROKEN_BUILD_RUNBOOK.md)
- [Broken CI](runbooks/BROKEN_CI_RUNBOOK.md)

## Prompts
- [Default Response Contract](prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md)
- [Finalize Any Build Task 100](prompts/FINALIZE_ANY_BUILD_TASK_100.md)
- [Run Autonomous Agent Army 100](prompts/RUN_AUTONOMOUS_AGENT_ARMY_100.md)
- [Safe Parallel Terminals 100](prompts/SAFE_PARALLEL_TERMINALS_100.md)
- [Final Boss Review Prompt 100](prompts/FINAL_BOSS_REVIEW_PROMPT_100.md)
- [DeepSeek Implementation Ticket 100](prompts/DEEPSEEK_IMPLEMENTATION_TICKET_PROMPT_100.md)
- [Production Safety Review 100](prompts/PRODUCTION_SAFETY_REVIEW_PROMPT_100.md)

## Reports
- [Sessions Archive](reports/sessions/)
- [Final 100 A+ Report](reports/FINAL_100_A_PLUS_AGENTIC_CODING_OS_REPORT.md)

## Root Files
- [CLAUDE.md](../../CLAUDE.md) — Boot instructions for Claude Code
- [AGENTS.md](../../AGENTS.md) — Rules for all coding agents
