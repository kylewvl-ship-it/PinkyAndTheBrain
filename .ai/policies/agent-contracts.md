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