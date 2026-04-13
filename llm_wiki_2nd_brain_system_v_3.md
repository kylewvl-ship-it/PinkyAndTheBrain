# LLM Wiki + Multi-Agent Dev + 2nd Brain System (v3)

---

## 🎯 Objective

Build a **local-first, tool-agnostic system** that:
- Compiles raw inputs into **traceable knowledge**
- Supports **real thinking and idea development**
- Uses LLMs as **bounded execution engines**
- Avoids lock-in, drift, and knowledge decay

---

# 🧠 Core Model

## System Flow

```
RAW → WORKING → WIKI (DERIVED)
          ↓
   CODE / TESTS / SCHEMAS (PRIMARY)
          ↓
   VALIDATION + AUDIT
```

---

# ⚖️ Authority Hierarchy (NON-NEGOTIABLE)

1. Code + passing tests → runtime truth  
2. Migrations / schemas / contracts → data truth  
3. ADRs → intended architecture  
4. Task files (accepted) → scoped decisions  
5. Wiki → synthesized knowledge  
6. Working notes → evolving interpretation  
7. Raw notes → unverified input  

> Wiki NEVER overrides primary artifacts

---

# 📁 Repo Structure (Minimal + Enforced)

```
repo/

src/ or apps/
tests/

knowledge/
  raw/
  working/
  wiki/
  schemas/

.ai/
  handoffs/
  policies/

scripts/

README.md
CLAUDE.md
AGENTS.md
```

### Rules
- No duplicate concepts across folders
- No new folders without justification
- If placement is unclear → system design is wrong

---

# 🧠 Knowledge System (2nd Brain Integrated)

## Layer Roles

| Layer | Role |
|------|------|
| raw/ | capture (fast, messy, no constraints) |
| working/ | thinking (active cognition layer) |
| wiki/ | stable knowledge (derived, structured) |
| schemas/ | enforceable contracts |

---

## 1. RAW (Capture Layer)

Purpose:
- frictionless input
- no structure required

Contains:
- ideas
- notes
- copied content
- partial thoughts

Rule:
> Optimize for speed, not quality

---

## 2. WORKING (Thinking Layer — CRITICAL)

This is the **actual 2nd brain**.

Purpose:
- develop ideas
- connect concepts
- explore
- refine understanding

### Template

```
# <Title>

## What I think

## Connections
[[linked-notes]]

## Questions

## Insights

## Next Steps
```

Rules:
- personal thinking allowed
- contradictions allowed
- incomplete ideas allowed
- MUST link to other notes

---

## 3. WIKI (Stable Knowledge)

Purpose:
- structured reference
- reusable knowledge
- distilled concepts

### Rules
- Derived from working/raw
- Must cite sources
- Must NOT override:
  - code
  - tests
  - schemas
  - ADRs

---

## Wiki Template (STRICT)

```
# <Title>

## Summary

## Key Concepts

## Details

## Relationships
[[links]]

## Open Questions

## Sources

## Metadata
- Status: draft | verified | stale | archived
- Last Updated:
- Last Verified:
- Confidence: high | medium | low
```

---

# 🧩 Compiler Rules (RAW/WORKING → WIKI)

### DO
- Preserve exact terms, paths, identifiers
- Track all sources explicitly
- Surface contradictions
- Distinguish fact vs inference

### DO NOT
- Merge conflicting ideas silently
- Invent missing details
- remove uncertainty

---

# 🧠 Retrieval Rules

## Coding Task
1. Task file
2. ADRs
3. Wiki
4. Code
5. Tests
6. Schemas

## Thinking / Research
1. Working notes
2. Wiki
3. Sources
4. Raw

Rule:
> High-impact decisions must verify against primary sources

---

# 🧾 Task System (Execution Layer)

All work starts at:
```
.ai/handoffs/<task>.md
```

## Template

```
# Task: <name>

## Goal

## Context

## Constraints

## Deliverables

## Done When

## Owner
## Status
## Dependencies

## Touched Paths

## Validation Commands

## Risks

## Rollback Plan

## Reviewer

## Decision Log

## Open Questions
```

---

# 🤖 Agent System (Contract-Based)

## Core Principle
Agents are defined by **output**, not intelligence

---

## Required Fields
- ROLE
- INPUT
- OUTPUT
- TOOLS
- RULES
- STOP CONDITIONS

---

## Agent Types

### Builder
Produces: code diff

### Auditor
Produces: critique

### Researcher
Produces: options + tradeoffs

### Validator
Produces: pass/fail

### Compiler
Produces: wiki pages

---

## Rules
- No overlapping responsibilities
- No vague outputs
- No self-approval

---

# 🔁 Workflow Modes

## Default
1. Builder
2. Validator
3. Auditor
4. Merge

## Exploration
1. Researcher
2. Decision
3. Builder

Rule:
> Builder and Auditor must remain separate

---

# 🧪 Validation Gates

All changes must pass:
- tests
- lint/type checks
- schema validation
- task completion criteria

---

# 🔁 Recall System (2nd Brain Requirement)

## Daily
- revisit 1–2 working notes

## Weekly
- review recent notes

## Always
- link new notes to old ones

Purpose:
- force connections
- prevent stagnation

---

# 🧭 Staleness Control

## Wiki
Mark stale if:
- source changed
- code changed
- contradictions appear

## Working
- evolves continuously
- never “final”

---

# 🚫 Anti-Patterns

- treating wiki as ground truth
- skipping working layer
- over-structuring raw input
- vague agents
- duplicating knowledge

---

# 🧠 System Reality

- LLMs are non-deterministic
- knowledge decays
- summaries are lossy

Therefore:
> Trust comes from validation + provenance

---

# 🧭 Bottom Line

- RAW = capture
- WORKING = thinking (core)
- WIKI = stable knowledge
- CODE/TESTS = truth
- TASKS = execution
- AGENTS = operators

---

# 🔥 Key Insight

> If the system does not make thinking easier, it will not be used

---

