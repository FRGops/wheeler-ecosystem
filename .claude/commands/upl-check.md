---
trigger: /upl-check
description: UPL compliance audit — verify no unauthorized practice of law. AI-generated legal content must have attorney review. No AI acts as attorney.
---

# /upl-check — Unauthorized Practice of Law Compliance

UPL is criminal in most states. AI-generated documents without attorney review = UPL risk. This is the single most important compliance boundary.

## Execution

### Step 1: Document Audit
Audit all AI-generated documents for attorney review compliance:
- SurplusAI document assembly: 100% attorney-reviewed before filing? [ ]
- AI-generated legal content: attorney review gate active? [ ]
- Document review metadata: reviewer, timestamp, changes made [ ]
- No document filed without attorney sign-off? [ ]

### Step 2: AI System Audit
Review all AI systems for UPL risk:
- Which systems generate content that could be "legal advice"? 
- Do claimants understand Wheeler is not a law firm?
- Are attorney review gates bypassable?
- Is AI EVER presented as providing legal services?

### Step 3: Marketing/Communications Audit
- Does any marketing imply Wheeler provides legal services?
- Are attorney advertising rules (ABA 7.1-7.5) followed?
- Do all communications include "Wheeler is not a law firm" disclosure?

### Step 4: State-Specific UPL Audit
- Tier 3 states (CA, FL, LA, MA, NJ, NY): what activities are UPL?
- Pro hac vice tracking for out-of-state attorney work
- Non-attorney staff: clear boundaries documented?

### Agent Dispatch
```
Agent(subagent_type="marketplace-compliance")  # Primary UPL check
Agent(subagent_type="claims-workflow-compliance") # Document review gates
Agent(subagent_type="state-rules")             # State UPL definitions
Agent(subagent_type="ai-governance")           # AI UPL boundaries
Agent(subagent_type="no-false-greens-legal")   # Independent verification
```

## Bright Lines (NEVER Cross)
1. AI NEVER provides legal advice
2. AI NEVER signs or files legal documents
3. AI-generated documents ALWAYS have attorney review
4. Wheeler NEVER presents itself as a law firm
5. Claimants ALWAYS know they can choose their own attorney

## Target: 100/100 = Zero UPL Risk
