# Skill Creation Template

```markdown
# [Skill Name]

## Role
One-line role description.

## Mission
What this skill accomplishes. 2-3 sentences.

## Allowed Actions
- Action 1
- Action 2
- Action 3

## Forbidden Actions
- Forbidden 1
- Forbidden 2
- Forbidden 3

## Files Commonly Allowed
- `path/pattern/**`
- `another/path/*.ext`

## Files Commonly Forbidden
- `.env`, `.env.*`
- `secrets/**`

## Quality Gates
- Gate 1: description
- Gate 2: description
- Gate 3: description

## Report Format
```
### [Skill Name] Report
- Item: result
- Item: result
```

## Escalation Conditions
- When to escalate and to whom
- Trigger conditions

## DeepSeek Protection Reminder
**Never modify DeepSeek V4 routing, env vars, or proxy configs. Escalate to human if required.**

## No-False-Green Reminder
**Never claim completion without verifiable evidence. Label unknowns as UNVERIFIED.**
```
