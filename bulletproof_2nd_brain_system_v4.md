# Bulletproof 2nd Brain + LLM Wiki + Multi-Agent Operating System (Hardened v4)

## Objective

Build a local-first, tool-agnostic system that:
- captures messy inputs without friction,
- develops ideas without losing uncertainty,
- compiles verified knowledge into durable reference,
- keeps execution grounded in primary artifacts,
- resists drift, hallucination, duplication, and abandonment.

---

## First Principles

1. **Primary artifacts beat summaries.**  
   Code, tests, migrations, contracts, and accepted task decisions outrank all derived notes.

2. **Thinking and knowledge are different jobs.**  
   Working notes are for exploration. Wiki pages are for stable reference. They must never collapse into one layer.

3. **Every durable claim needs provenance.**  
   No uncited “facts” in wiki pages.

4. **The system must survive partial use.**  
   If you skip a day, switch tools, or stop using agents for a week, the system should still hold up.

5. **The system must be cheaper to maintain than to ignore.**  
   If upkeep becomes heavy, the system dies.

---

## Canonical Flow

```text
CAPTURE → TRIAGE → WORKING → COMPILE → VERIFY → PUBLISH → REVIEW
   |         |         |         |         |         |         |
 raw/     inbox     working/    draft     checks     wiki/    stale/archive
```

### Meaning
- **Capture**: dump ideas fast.
- **Triage**: decide whether the note matters.
- **Working**: think, connect, refine.
- **Compile**: turn candidate knowledge into structured pages.
- **Verify**: check against primary sources.
- **Publish**: move into wiki.
- **Review**: re-check for staleness, contradiction, or irrelevance.

---

## Authority Hierarchy (Non-Negotiable)

1. Code + passing tests = runtime truth  
2. Migrations / schemas / contracts / APIs = data truth  
3. ADRs = intentional architectural truth  
4. Accepted task files / change records = scoped implementation truth  
5. Wiki = derived reference  
6. Working notes = exploratory reasoning  
7. Raw notes = unverified capture

### Hard Rule
**No derived layer may override a higher layer.**  
If a wiki page conflicts with code, the wiki is wrong until repaired.

---

## Repo Structure

```text
repo/
  src/ | apps/
  tests/
  migrations/ | db/ | contracts/

  knowledge/
    inbox/
    raw/
    working/
    wiki/
    reviews/
    schemas/
    archive/

  .ai/
    handoffs/
    policies/
    prompts/
    audits/

  scripts/

  README.md
  AGENTS.md
  CLAUDE.md
  CODEX.md
```

### Folder Semantics
- **inbox/**: temporary intake buffer; must be emptied regularly.
- **raw/**: captured material worth keeping but not yet processed.
- **working/**: active thought development.
- **wiki/**: verified, reusable reference.
- **reviews/**: periodic audit logs and stale reports.
- **schemas/**: templates and machine-enforced structures.
- **archive/**: intentionally retired notes, not soft-deleted clutter.

### Structural Rules
- No duplicate concept pages in multiple stable folders.
- No “misc”, “temp2”, “new folder”, or other entropy sinks.
- New folders require a written reason in an ADR or repo note.
- If two folders seem to serve the same purpose, merge them.

---

## The 2nd Brain Layers

## 1. Inbox
Purpose:
- fastest possible capture
- minimal friction
- no organizational burden at capture time

Allowed content:
- fleeting thoughts
- copied snippets
- links without commentary
- questions
- tasks to sort later

Rules:
- Inbox is disposable.
- Anything left untouched after a fixed review window is archived or deleted.
- Inbox is not a knowledge base.

---

## 2. Raw
Purpose:
- preserve source material before interpretation

Allowed content:
- meeting notes
- copied research
- excerpts
- brainstorm fragments
- imported documents
- unstructured logs

Rules:
- Raw is append-friendly.
- Raw may be messy.
- Raw must not be treated as a reliable source without verification.
- Raw should preserve timestamps and origin where possible.

---

## 3. Working
Purpose:
- actual thinking
- synthesis
- comparison
- framing problems
- developing beliefs cautiously

This is the real 2nd brain layer.

### Working Note Template

```md
# <Title>

## Status
active | blocked | incubating | abandoned

## Prompt / Trigger
Why this note exists

## What I think
Current best interpretation

## Evidence
- source / observation
- source / observation

## Connections
[[linked-note]]
[[related-concept]]

## Tensions / Contradictions
What does not fit yet

## Open Questions
- question
- question

## Next Moves
- action
- action

## Source Pointers
- raw/<file>
- wiki/<page>
- src/<path>
```

### Working Rules
- Personal interpretation is allowed.
- Contradictions are mandatory to record, not embarrassing to hide.
- A working note without links is weak.
- A working note can die without becoming a wiki page.
- Not every thought deserves promotion.

---

## 4. Wiki
Purpose:
- durable reference
- reusable knowledge
- orientation layer for future work

### Entry Criteria
A page belongs in wiki only if it is:
- likely to be reused,
- understandable by future-you,
- grounded in sources,
- not merely a transient thought.

### Wiki Page Template

```md
# <Title>

## Summary
Short factual overview

## Why it matters
Why future-you should care

## Key Concepts
- concept
- concept

## Details
Structured explanation

## Relationships
[[linked-page]]

## Contradictions / Caveats
Known uncertainty or competing interpretations

## Sources
- primary:
- secondary:

## Metadata
- Status: draft | verified | stale | archived
- Last Updated:
- Last Verified:
- Confidence: high | medium | low
- Owner:
- Review Trigger:
```

### Wiki Rules
- Every meaningful claim must trace back to a source.
- Confidence applies to claims, not vibes.
- “Verified” means checked against primary artifacts when available.
- Pages without a clear owner or review trigger decay silently.
- If a page is not useful, archive it instead of letting it rot.

---

## 5. Archive
Purpose:
- preserve history without polluting retrieval

Rules:
- Archive is searchable but excluded from default retrieval.
- Archived pages must state why they were archived.
- Never delete important context just to keep the system “clean.”

---

## Knowledge Promotion Rules

### Promotion Path
- inbox → raw when worth keeping
- raw → working when worth thinking about
- working → wiki when verified and reusable
- wiki → archive when stale, replaced, or no longer useful

### Promotion Tests
A note moves upward only if:
1. it has a stable purpose,
2. it has traceable sources,
3. it is likely to matter again,
4. it is clearer than the layer below it.

If not, it stays where it is or gets archived.

---

## Compiler Rules (Raw / Working → Wiki)

### Must Do
- preserve exact identifiers, paths, names, APIs, commands
- separate fact, inference, and speculation
- record contradictions explicitly
- carry forward source links
- preserve unresolved uncertainty

### Must Not Do
- silently merge conflicting claims
- invent missing details
- strip nuance for neatness
- summarize primary sources beyond usefulness
- create pages whose only function is aesthetic completeness

### Output Contract
Every compiled page should answer:
- What is true?
- How do we know?
- What remains uncertain?
- What should be checked next?

---

## Retrieval Policy

### For Coding / Implementation
Order of retrieval:
1. active task file
2. relevant ADRs
3. contracts / migrations / schemas
4. code
5. tests
6. wiki
7. working notes
8. raw / archive only if needed

### For Research / Strategy / Thinking
Order of retrieval:
1. working notes
2. wiki
3. source material
4. raw
5. archive

### Default Retrieval Safeguards
- Exclude archive by default.
- Prefer fewer high-trust sources over many low-trust summaries.
- If stakes are high, force verification against primary artifacts.
- Retrieval should return provenance, not just content.

---

## Task System (Execution Layer)

All meaningful work starts with a task file.

Path:
```text
.ai/handoffs/<task>.md
```

### Required Task Template

```md
# Task: <name>

## Goal
Single concrete outcome

## Why
Business or system reason

## Context
Relevant background only

## Constraints
Hard boundaries

## Assumptions
What is believed but not yet proven

## Deliverables
Files / outputs expected

## Done When
Acceptance criteria

## Dependencies
People, systems, files, prerequisites

## Touched Paths
Expected file impact

## Validation Commands
Exact checks to run

## Risks
What can break

## Rollback Plan
How to reverse safely

## Decision Log
Important choices and why

## Open Questions
Unresolved items

## Owner
## Reviewer
## Status
```

### Task Rules
- One task = one clear outcome.
- Ambiguous tasks cause bad agent behavior.
- Every task must define validation before execution.
- “Done” without explicit checks is fake.

---

## Agent System

## Principle
Agents are role contracts, not magic personalities.

### Required Agent Contract
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

### Minimum Agent Set
- **Builder** → proposes implementation
- **Auditor** → attacks assumptions, defects, regressions
- **Researcher** → options and tradeoffs
- **Validator** → pass/fail against explicit checks
- **Compiler** → promotes notes into wiki format
- **Curator** → triages inbox/raw and manages staleness

### Hard Separation Rules
- Builder cannot self-approve.
- Auditor cannot author final implementation.
- Validator cannot redefine acceptance criteria.
- Compiler cannot upgrade a page to verified without evidence.
- Curator cannot delete material without an archive decision.

### Failure Rule
If two agents can produce the same output with the same authority, the design is bad.

---

## Workflow Modes

## Delivery Mode
1. Research only if needed
2. Builder drafts
3. Validator checks
4. Auditor attacks
5. Builder revises
6. Merge only after checks pass
7. Compiler updates wiki if durable learning emerged

## Exploration Mode
1. Researcher expands options
2. Working note captures reasoning
3. Decision made by human or explicit rule
4. Builder executes only after decision

## Knowledge Mode
1. Curator triages notes
2. Compiler drafts wiki page
3. Validator checks provenance
4. Owner marks verified or leaves draft

---

## Validation Gates

Any durable system change should define relevant checks from this list:
- unit/integration tests
- type checks
- lint
- schema validation
- migration verification
- contract compatibility
- documentation update
- provenance check for wiki changes
- stale link check
- duplication scan

### Knowledge Validation
A wiki page is not “verified” unless:
- sources exist,
- primary artifacts were checked where available,
- contradictions are surfaced,
- metadata is complete.

---

## Staleness Control

### Review Triggers
A wiki page becomes suspect when:
- code changes,
- contracts or schemas change,
- ADRs are superseded,
- linked sources move,
- contradictions emerge,
- no one has reviewed it within the review window.

### States
- **draft**: compiled but not yet trusted
- **verified**: checked and currently trusted
- **stale**: likely outdated
- **archived**: intentionally retired

### Review Cadence
- Daily: empty inbox and scan active working notes
- Weekly: review changed wiki pages and open contradictions
- Monthly: stale sweep, duplication sweep, archive dead notes
- Per release: verify pages tied to changed code/contracts

---

## Duplication Policy

Duplication is one of the main ways these systems rot.

### Rules
- One canonical page per concept.
- Synonyms redirect to canonical pages.
- Repeated summaries across pages should be replaced with links.
- Task-specific context belongs in tasks, not copied into wiki pages.
- Working notes may overlap temporarily; wiki pages should not.

---

## Metadata Policy

Every durable note must carry enough metadata to survive context loss.

### Minimum Metadata for Wiki
- status
- owner
- confidence
- last updated
- last verified
- review trigger
- source list

### Minimum Metadata for Working
- status
- trigger
- next move
- source pointers

Without metadata, notes become orphaned text.

---

## Human Factors

This system fails if it becomes performative.

### Therefore:
- Capture must be frictionless.
- Triage must be quick.
- Working notes must feel useful, not ceremonial.
- Wiki pages must earn their existence.
- Review rituals must be small enough to keep.

### Practical Rule
When in doubt, reduce process before adding more structure.

---

## Anti-Patterns

- treating the wiki as ground truth
- promoting notes because they feel important, not because they are useful
- skipping working notes and pretending raw input is understanding
- letting inbox become permanent storage
- vague agent responsibilities
- no validation commands in tasks
- “verified” pages with no provenance
- duplication across wiki, tasks, and docs
- keeping stale notes visible in default retrieval
- optimizing for elegance over survivability

---

## Operating Maxims

- Primary artifacts beat memory.
- Uncertainty written down is strength.
- A smaller trusted wiki beats a large decaying one.
- Every summary is lossy.
- Good retrieval starts with good hierarchy.
- The system should help you think, not cosplay productivity.

---

## Bottom Line

- **Inbox** = frictionless capture
- **Raw** = preserved input
- **Working** = real thinking
- **Wiki** = verified reusable knowledge
- **Primary artifacts** = truth
- **Tasks** = execution control
- **Agents** = bounded operators
- **Validation + provenance** = trust

## Final Rule

If a layer does not make future decisions safer, faster, or clearer, it should be simplified or removed.
