# Agent Contracts

## Required Contract Fields
- ROLE
- PURPOSE
- INPUTS
- OUTPUTS
- TOOLS ALLOWED
- TOOLS FORBIDDEN
- DECISION RIGHTS
- STOP CONDITIONS
- ESCALATION CONDITIONS
- VALIDATION EXPECTED

## Handoff File Schema

Agent handoffs live in `.ai/handoffs/` as Markdown files with YAML frontmatter:

```yaml
---
title: "Concrete task title"
status: "draft"
owner: "Reno"
agent_role: "Builder"
created: "YYYY-MM-DD"
updated: "YYYY-MM-DD"
source_list: []
validation_commands: []
private: false
---
```

Allowed `status` values:
- `draft`: still being shaped.
- `ready-for-dev`: implementation can begin.
- `in-progress`: actively being changed.
- `in-review`: ready for independent review.
- `done`: completed and validated.

Required body sections:
- Goal
- Context
- Constraints
- Deliverables
- Done When
- Validation Commands
- Risks
- Rollback Plan

Validation command:
- Run `.\scripts\health-check.ps1 -Type metadata` before treating a handoff as durable context.

## Minimum Agent Set
- Builder: proposes implementation.
- Auditor: attacks assumptions, defects, and regressions.
- Researcher: provides options and tradeoffs.
- Validator: reports pass/fail against explicit checks.
- Compiler: promotes notes into wiki format.
- Curator: triages inbox/raw and manages staleness.

## Separation Rules
- Builder cannot self-approve.
- Auditor cannot author final implementation.
- Validator cannot redefine acceptance criteria.
- Compiler cannot mark wiki pages verified without evidence.
- Curator cannot delete material without an archive decision.
