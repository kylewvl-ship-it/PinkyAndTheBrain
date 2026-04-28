---
stepsCompleted:
  - issue-summary
  - impact-analysis
  - recommended-approach
  - detailed-change-proposals
  - implementation-handoff
workflowType: 'correct-course'
project_name: 'PinkyAndTheBrain'
user_name: 'Reno'
date: '2026-04-24'
change_trigger: 'Selective adoption of high-value OB1 ideas without abandoning PinkyAndTheBrain local-first governance model.'
change_scope: 'moderate'
recommended_mode: 'batch'
inputDocuments:
  - "_bmad-output/planning-artifacts/prd.md"
  - "_bmad-output/planning-artifacts/epics.md"
  - "_bmad-output/planning-artifacts/architecture.md"
  - "README.md"
  - "bulletproof_2nd_brain_system_v4.md"
  - "https://github.com/NateBJones-Projects/OB1/blob/main/README.md"
  - "https://github.com/NateBJones-Projects/OB1/blob/main/docs/01-getting-started.md"
  - "https://github.com/NateBJones-Projects/OB1/blob/main/server/index.ts"
  - "https://github.com/NateBJones-Projects/OB1/blob/main/schemas/enhanced-thoughts/schema.sql"
---

# Sprint Change Proposal - OB1-Informed Direction Correction

## Section 1: Issue Summary

### Triggering Context

This change was triggered during planning review rather than by a failed implementation story. The gap surfaced while comparing PinkyAndTheBrain's current PRD, architecture, and Epic 3 / Epic 4 story set against `OB1`.

**Triggering story cluster**

- `3.1 Cross-Layer Knowledge Search`
- `3.3 AI Handoff Context Generation`
- `4.1 AI Conversation Import`
- `4.2 Non-AI Source Capture`
- `4.3 Capture Configuration Management`

### Problem Statement

PinkyAndTheBrain was intentionally designed as a Markdown-first, local-first knowledge operating system with strong review gates, provenance rules, and explicit knowledge layers. That direction remains correct.

The problem is narrower: the current plan is strong on governance and weak on reusable ingestion, derived metadata, duplicate detection, and machine-facing retrieval interfaces. If left unchanged, retrieval and capture will remain workable for a single-user manual flow but underpowered for multi-agent reuse and higher-volume import workflows.

### Evidence From Current Artifacts

- In `_bmad-output/planning-artifacts/epics.md`, Story `3.1` is still file/text-match oriented and does not define metadata-filtered or adapter-backed retrieval.
- Story `3.3` builds AI handoff context from keyword search and static markdown output only; it does not define a machine-facing retrieval surface.
- Story `4.1` preserves imported conversations as raw text but does not define recipe modules, extraction outputs, or dedup fingerprints.
- Story `4.2` captures provenance manually but does not define optional extraction or duplicate review after capture.
- Story `4.3` covers paths, review cadence, and templates, but not extraction strictness, dedup rules, or derived-index settings.
- In `_bmad-output/planning-artifacts/architecture.md`, the architecture stops at file-based contracts and local vault automation; it does not yet define canonical-vs-derived boundaries for optional MCP or retrieval adapters.
- In `_bmad-output/planning-artifacts/prd.md`, the PRD correctly rejects a database-first core, but it does not clearly describe which derived adapters are allowed once the manual workflow is validated.

### Issue Type

- Strategic refinement based on external comparison
- New requirement clarity for retrieval and capture ergonomics
- Not a rollback-triggering implementation failure

### Core Correction Decision

Adopt `OB1` ideas at the adapter layer, not at the authority layer.

In practical terms:

- Keep Markdown knowledge artifacts and knowledge layers as the canonical system of record.
- Add optional derived artifacts for metadata extraction, deduplication, retrieval indexes, and agent-facing access.
- Require every derived artifact to stay rebuildable from canonical Markdown and remain subordinate to review gates.
- Do not re-center the system around a hosted database, a mandatory remote service, or automatic trust in extracted metadata.

## Section 2: Impact Analysis

### Checklist Status Summary

- `1.1 Triggering story identified`: `[x] Done`
- `1.2 Core problem defined`: `[x] Done`
- `1.3 Supporting evidence gathered`: `[x] Done`
- `2.1-2.5 Epic impact assessed`: `[x] Done`
- `3.1 PRD conflict review`: `[x] Done`
- `3.2 Architecture conflict review`: `[x] Done`
- `3.3 UI/UX conflict review`: `[N/A]`
- `3.4 Other artifact impact review`: `[!] Action-needed after approval`
- `4.1-4.4 Path forward evaluated`: `[x] Done`
- `5.1-5.5 Proposal and handoff defined`: `[x] Done`
- `6.4 sprint-status.yaml update`: `[!] Pending proposal approval`

### Epic Impact

**Affected epics**

- **Epic 3: Knowledge Discovery & Retrieval**
  - Story scope expands from keyword/file search into hybrid retrieval: text match, metadata filtering, and optional derived retrieval adapters.
  - Story order inside the epic should change so retrieval abstraction is defined before optional agent-facing surfaces.
- **Epic 4: Advanced Capture & Sources**
  - Becomes the main home for `OB1` borrowing: recipe-based ingestion, extraction outputs, and content fingerprinting.
  - Story `4.3` should move earlier conceptually because configuration needs to define recipe/extraction behavior before advanced capture automation is implemented.
- **Epic 6: System Health & Maintenance**
  - Existing health checks need modest extension to validate extraction confidence, duplicate fingerprints, and derived-index drift.
- **Epic 7: System Reliability & NFR Compliance**
  - Needs explicit guardrails for inspectable derived artifacts, rebuildability, and auditability of extraction/dedup decisions.

**Epics not redefined**

- **Epic 1: Basic Knowledge Lifecycle**
  - No change to inbox, triage, or working-note fundamentals.
- **Epic 2: Knowledge Quality & Promotion**
  - No weakening of promotion review gates; these become more important once extraction is introduced.
- **Epic 5: Privacy & Project Management**
  - No structural change, but privacy rules must continue to apply to any future machine-facing retrieval interface.
- **Epic 0: System Foundation**
  - No separate new epic required. Foundation only needs room for derived-artifact directories/config if the change is approved.

### Story Impact

**Stories requiring direct edits**

- `3.1 Cross-Layer Knowledge Search`
- `3.3 AI Handoff Context Generation`
- `4.1 AI Conversation Import`
- `4.2 Non-AI Source Capture`
- `4.3 Capture Configuration Management`
- `6.1 Automated Health Checks`
- `6.2 Health Check Finding Resolution`
- `7.3 Inspectable Automation`

**New story decision**

No new epic is required. A separate new story is also not strictly required if the above stories are expanded correctly. The smallest correct change is to fold the new direction into existing Story `3.1`, `3.3`, `4.1`, `4.2`, `4.3`, `6.1`, `6.2`, and `7.3` rather than adding parallel stories that fragment ownership.

### Artifact Conflicts

**PRD conflicts**

- `Technical Success` currently says the system "does not need to remain Markdown-only," which is too loose for the desired canonical-vs-derived boundary.
- `Growth Features` is directionally aligned but does not explicitly name recipe-based ingestion, derived metadata, or optional agent-facing adapters.
- `Developer Tool Specific Requirements` still describes a command-oriented local tool, but it does not define derived-index or adapter boundaries.

**Architecture conflicts**

- `Knowledge Processing Architecture` describes ingest/query/lint/maintain but does not define optional extraction and derived indexing as rebuildable subordinate layers.
- `Agent Integration Architecture` is file-contract focused and needs a rule that any MCP exposure is derived from canonical Markdown rather than becoming a new source of truth.
- `Infrastructure & Deployment Architecture` needs an explicit place for derived artifacts and rebuild procedures.

**UI/UX conflicts**

- No UX or UI design artifact exists in `_bmad-output/planning-artifacts`.
- No user-facing UI redesign is required for this correction because the change is still workflow/script/Obsidian oriented.
- If a UX document is added later, it should cover configuration visibility for extraction strictness, dedup review, and adapter enablement.

**Other artifact impacts**

- `README.md` should eventually reflect the canonical-vs-derived rule and optional adapter direction after proposal approval.
- `sprint-status.yaml` should only be updated after approval so story scope changes are reflected in backlog status cleanly.

### Technical Impact

- No forced infrastructure migration
- No required hosted service
- No required database adoption
- Added architectural rule:
  - canonical knowledge stays in Markdown
  - derived metadata/indexes are rebuildable artifacts
  - adapter surfaces can read derived artifacts but cannot outrank canonical files
- Added implementation concern:
  - extraction, deduplication, and retrieval ranking must remain reviewable and reversible

### Risk Analysis

**If ignored**

- Retrieval remains too shallow for later multi-agent use.
- Import workflows remain manual in the wrong places.
- Duplicate capture and weak metadata quality will create friction as volume increases.

**If over-applied**

- PinkyAndTheBrain drifts into a memory database product with weaker trust controls.
- Derived metadata starts being treated as authoritative.
- Review gates get bypassed by automation convenience.

## Section 3: Recommended Approach

### Option Evaluation

**Option 1: Direct Adjustment**

- Viable: `Yes`
- Effort: `Medium`
- Risk: `Low-Medium`
- Reason: existing epics already contain the right ownership boundaries; they need sharper acceptance criteria, not a new product plan.

**Option 2: Potential Rollback**

- Viable: `No`
- Effort: `High`
- Risk: `Unnecessary`
- Reason: this issue was found during planning review, not after expensive implementation. There is nothing meaningful to roll back.

**Option 3: PRD MVP Review**

- Viable: `Partially`
- Effort: `Medium`
- Risk: `Medium`
- Reason: an MVP review would be useful only to clarify what stays optional. It is not necessary to reduce scope or redefine the product goal.

### Selected Path

**Direct Adjustment with guardrails**

The correct move is to keep the current MVP and planning structure, but tighten it so optional adapter capabilities are clearly permitted and clearly bounded.

### What To Borrow

1. **Recipe-based ingestion**
   - Why: modular imports are a better fit than one-off capture logic.
   - Constraint: all imports land in inbox/raw or reviewable staging first.

2. **Structured extraction outputs**
   - Why: extracted metadata improves triage, retrieval, and review throughput.
   - Constraint: extracted metadata is advisory until reviewed.

3. **Content fingerprint deduplication**
   - Why: duplicate capture is cheap to detect and expensive to ignore later.
   - Constraint: dedup findings must be visible, reviewable, and reversible.

4. **Hybrid retrieval**
   - Why: exact text, metadata filters, and later semantic ranking solve different retrieval problems.
   - Constraint: provenance and confidence must be preserved in all retrieval outputs.

5. **Optional agent-facing adapter surfaces**
   - Why: machine-friendly retrieval improves reuse across tools.
   - Constraint: any such interface must be derived from canonical files and stay optional.

### What Not To Borrow

1. Hosted database as required core storage
2. Single-schema "everything is a thought" domain model
3. Implicit trust in extracted metadata
4. Architecture where remote memory becomes more authoritative than local Markdown

### Rationale

This path was chosen because it preserves the product thesis while removing a real planning blind spot:

- PinkyAndTheBrain remains a knowledge refinery, not just a memory store.
- Local Markdown remains portable, inspectable, and reviewable.
- Automation improves throughput without changing the trust model.

### MVP and Timeline Impact

- MVP remains intact.
- No epic is removed.
- Planning artifacts need moderate edits now.
- Implementation sequence changes slightly:
  1. clarify adapter/config boundaries
  2. add recipe/extraction/dedup story criteria
  3. extend retrieval stories
  4. extend health/inspectability guardrails
  5. consider optional MCP exposure last

## Section 4: Detailed Change Proposals

### PRD Modification 1

**Artifact:** `_bmad-output/planning-artifacts/prd.md`  
**Section:** `Technical Success`

**OLD**

The MVP should support automatic AI conversation capture inspired by `claude-memory-compiler`, then convert captured sessions into structured knowledge that can be promoted, searched, and checked. The system does not need to remain Markdown-only, but Markdown and Obsidian compatibility remain important constraints because the knowledge base must stay local-first, inspectable, and easy to edit.

**NEW**

The MVP should support AI conversation capture and conversion into structured knowledge that can be promoted, searched, and checked. Canonical knowledge artifacts remain Markdown-first and Obsidian-compatible. The system may introduce derived metadata caches, dedup fingerprints, retrieval indexes, or optional agent-facing adapters after the manual workflow proves itself, but those derived artifacts must be rebuildable from canonical Markdown and may not bypass review gates or become a higher-authority source of truth.

**Rationale**

This keeps the local-first rule explicit while still allowing selective `OB1`-style leverage.

### PRD Modification 2

**Artifact:** `_bmad-output/planning-artifacts/prd.md`  
**Section:** `Growth Features (Post-MVP)`

**OLD**

Post-MVP growth features may include deeper Obsidian integration, richer retrieval interfaces, automated deduplication suggestions, contradiction detection across related pages, configurable review schedules, multi-agent review workflows, and dashboards for knowledge health.

**NEW**

Post-MVP growth features may include deeper Obsidian integration, recipe-based source imports, structured metadata extraction, content fingerprint deduplication, richer retrieval interfaces that combine text and metadata search, optional semantic ranking adapters, optional MCP-based agent access derived from canonical knowledge files, configurable review schedules, multi-agent review workflows, and dashboards for knowledge health.

**Rationale**

The intended direction becomes explicit instead of staying implied.

### PRD Modification 3

**Artifact:** `_bmad-output/planning-artifacts/prd.md`  
**Section:** `Developer Tool Specific Requirements -> API Surface`

**OLD**

- Capture or import AI conversation logs.
- Create or update raw capture entries.
- Promote reviewed knowledge into wiki-ready Markdown.
- Run health checks for metadata, broken links, stale review dates, duplicates, unsupported claims, and orphaned pages.
- Search or retrieve relevant knowledge for an agent handoff.
- Generate or refresh indexes used for retrieval and navigation.

**NEW**

- Capture or import AI conversation logs through recipe-driven handlers where useful.
- Create or update raw capture entries and reviewable extraction outputs.
- Promote reviewed knowledge into wiki-ready Markdown.
- Run health checks for metadata, broken links, stale review dates, duplicates, unsupported claims, orphaned pages, extraction confidence gaps, and derived-index drift.
- Search or retrieve relevant knowledge for an agent handoff using text and metadata-aware retrieval.
- Generate, refresh, and rebuild derived indexes used for retrieval and navigation without changing canonical Markdown authority.
- Optionally expose curated retrieval through an agent-facing adapter only after the canonical-vs-derived boundary is enforced.

**Rationale**

This aligns the command surface with the proposed architecture instead of leaving adapter behavior undefined.

### Architecture Modification 1

**Artifact:** `_bmad-output/planning-artifacts/architecture.md`  
**Section:** `Knowledge Processing Architecture`

**OLD**

- **Manual capture**: Templates and folder drops for immediate capture
- **Agent hooks**: BMad agents write structured outputs to staging areas
- **Batch processing**: Scheduled processing of accumulated inputs
- **Review gates**: Human approval required before wiki promotion (NFR-003)

**NEW**

- **Manual capture**: Templates and folder drops for immediate capture
- **Recipe-based ingestion**: Source-specific handlers normalize imports into raw/staging formats
- **Structured extraction**: Optional metadata extraction, fingerprint generation, and duplicate analysis create reviewable derived artifacts
- **Agent hooks**: BMad agents write structured outputs to staging areas
- **Batch processing**: Scheduled processing of accumulated inputs
- **Review gates**: Human approval required before wiki promotion (NFR-003)
- **Authority rule**: extraction outputs and indexes are derived artifacts, rebuildable from canonical Markdown, and never outrank accepted knowledge files

**Rationale**

This is the smallest architecture extension that absorbs the new direction without changing the product core.

### Architecture Modification 2

**Artifact:** `_bmad-output/planning-artifacts/architecture.md`  
**Section:** `Agent Integration Architecture`

**OLD**

- **File-based contracts**: Agents read/write specific file formats in `.ai/handoffs/`
- **obsidian-cli integration**: Standardized vault operations for link updates, file moves
- **Context injection**: Agents receive relevant wiki content via file-based handoff
- **Output capture**: Agent conversations structured into reviewable formats

**NEW**

- **File-based contracts**: Agents read/write specific file formats in `.ai/handoffs/`
- **obsidian-cli integration**: Standardized vault operations for link updates, file moves
- **Context injection**: Agents receive relevant wiki content via file-based handoff
- **Derived retrieval adapters**: optional machine-facing retrieval surfaces may be added for curated access to canonical knowledge
- **Output capture**: Agent conversations structured into reviewable formats
- **Authority rule**: any MCP or adapter surface is read-only or review-gated against canonical Markdown artifacts and cannot become the primary write path

**Rationale**

This allows optional agent interoperability without changing the authority model.

### Architecture Modification 3

**Artifact:** `_bmad-output/planning-artifacts/architecture.md`  
**Section:** `Infrastructure & Deployment Architecture`

**OLD**

- **Storage**: Git repository of Markdown files with version history
- **Backup**: Automated git commits + external backup sync
- **Sync**: Git-based synchronization across devices
- **Performance**: Index-based navigation (index.md) + optional search tools

**NEW**

- **Storage**: Git repository of canonical Markdown files with version history
- **Derived artifacts**: rebuildable metadata caches, fingerprints, and retrieval indexes stored separately from canonical knowledge files
- **Backup**: Automated git commits + external backup sync
- **Sync**: Git-based synchronization across devices
- **Performance**: Index-based navigation (index.md), metadata-aware retrieval, and optional derived search adapters
- **Recovery rule**: derived artifacts can be deleted and rebuilt without loss of canonical knowledge

**Rationale**

The boundary between durable knowledge and derived support artifacts must be explicit.

### Epic Modification 1

**Artifact:** `_bmad-output/planning-artifacts/epics.md`  
**Section:** `Story 3.1: Cross-Layer Knowledge Search`

**OLD**

- **Then** results are returned from all knowledge layers using file content and metadata matching
- **And** results are ranked by: exact title match > exact content match > partial content match > metadata match
- **And** each result shows: filename, knowledge layer, last modified date, and 2-line preview

**NEW**

- **Then** results are returned from all knowledge layers using text search plus metadata-aware filtering
- **And** results are ranked by: exact title match > curated metadata match > exact content match > partial content match
- **And** each result shows: filename, knowledge layer, last modified date, provenance/source pointer, confidence indicator when available, and 2-line preview
- **And** the search workflow can optionally consume a rebuildable derived index without making that index authoritative
- **And** archived content remains excluded by default unless explicitly requested

**Rationale**

This adds hybrid retrieval without changing the search story into a database story.

### Epic Modification 2

**Artifact:** `_bmad-output/planning-artifacts/epics.md`  
**Section:** `Story 3.3: AI Handoff Context Generation`

**OLD**

- **Then** the system searches for relevant wiki pages and working notes using keyword matching
- **And** it prioritizes wiki content over working notes over raw content
- **And** it outputs a structured markdown file with: task context, relevant wiki excerpts, working note summaries, and source references

**NEW**

- **Then** the system searches for relevant wiki pages, working notes, and approved raw context using keyword and metadata-aware retrieval
- **And** it prioritizes accepted wiki content over working notes over raw content, with low-confidence or conflicting context clearly labeled
- **And** it outputs a structured markdown file with task context, relevant excerpts, source references, confidence notes, and retrieval rationale
- **And** the same retrieval contract can later back an optional agent-facing adapter without changing canonical storage rules

**Rationale**

The story should describe a reusable retrieval contract, not only a one-off markdown export.

### Epic Modification 3

**Artifact:** `_bmad-output/planning-artifacts/epics.md`  
**Section:** `Story 4.1: AI Conversation Import`

**OLD**

- **Then** the conversation is saved to the raw folder with timestamp and filename format: YYYY-MM-DD-HH-MM-conversation-[service].md
- **And** the import preserves the exact conversation text without modification
- **And** the frontmatter includes: conversation_date, ai_service, import_date, and review_status: "pending"
- **Then** I can manually select and copy sections for promotion to working notes

**NEW**

- **Then** the conversation is saved to the raw folder with timestamp and filename format: YYYY-MM-DD-HH-MM-conversation-[service].md
- **And** the import preserves the exact conversation text without modification as the canonical raw record
- **And** the frontmatter includes: conversation_date, ai_service, import_date, review_status: "pending", import_recipe, and extraction_status
- **And** the import may optionally produce a separate reviewable extraction artifact containing candidate metadata, topics, decisions, and source spans
- **Then** I can review extraction output, manually select sections for promotion, and trace every promoted item back to the unchanged raw conversation file

**Rationale**

This adds `OB1`'s useful extraction pattern without trusting the extraction by default.

### Epic Modification 4

**Artifact:** `_bmad-output/planning-artifacts/epics.md`  
**Section:** `Story 4.2: Non-AI Source Capture`

**OLD**

- **Then** the system saves the URL, page title, and capture date to frontmatter
- **And** I manually add my own summary, quotes, or notes in the content body
- **And** the captured content is saved to inbox with source_type: "web" in metadata

**NEW**

- **Then** the system saves the URL, page title, and capture date to frontmatter
- **And** I can still add my own summary, quotes, or notes in the content body
- **And** the captured content is saved to inbox or raw with source_type metadata appropriate to the source
- **And** the capture workflow may optionally generate a fingerprint and candidate metadata for duplicate review and later retrieval
- **And** any generated metadata remains reviewable and editable before it influences promotion or retrieval

**Rationale**

This strengthens non-AI capture ergonomics without weakening provenance rules.

### Epic Modification 5

**Artifact:** `_bmad-output/planning-artifacts/epics.md`  
**Section:** `Story 4.3: Capture Configuration Management`

**OLD**

- **Then** I can specify custom paths for inbox, raw, working, wiki, and archive folders
- **And** I can set filename patterns with variables like {date}, {time}, {source_type}
- **And** invalid path configurations show clear error messages with suggested fixes

**NEW**

- **Then** I can specify custom paths for inbox, raw, working, wiki, archive, and derived-artifact locations where needed
- **And** I can set filename patterns with variables like {date}, {time}, {source_type}
- **And** I can configure import recipes, extraction strictness, dedup behavior, and retrieval-index rebuild settings
- **And** invalid configurations show clear error messages with suggested fixes
- **And** any optional adapter or derived-index setting is clearly marked as non-canonical support infrastructure

**Rationale**

Configuration has to define the new behavior first or the implementation will drift.

### Epic Modification 6

**Artifact:** `_bmad-output/planning-artifacts/epics.md`  
**Section:** `Story 6.1: Automated Health Checks`

**OLD**

- **Then** findings are grouped by type: Missing Metadata, Broken Links, Stale Content, Duplicates, Orphans
- **And** each finding shows: file path, issue type, severity (high/medium/low), and suggested repair action

**NEW**

- **Then** findings are grouped by type: Missing Metadata, Broken Links, Stale Content, Duplicates, Orphans, Extraction Confidence Gaps, Derived Index Drift
- **And** each finding shows: file path, issue type, severity (high/medium/low), rule triggered, and suggested repair action
- **And** duplicate findings distinguish title similarity from fingerprint-based duplicate candidates
- **And** health checks can verify whether derived retrieval artifacts are stale relative to canonical files

**Rationale**

Once extraction and derived indexes exist, health checks need to police them.

### Epic Modification 7

**Artifact:** `_bmad-output/planning-artifacts/epics.md`  
**Section:** `Story 6.2: Health Check Finding Resolution`

**OLD**

- **And** I can choose from actions like: update metadata, fix link, merge duplicate, archive file, or defer

**NEW**

- **And** I can choose from actions like: update metadata, accept or reject extracted metadata, fix link, merge duplicate, ignore fingerprint match, rebuild a stale derived index, archive file, or defer

**Rationale**

Resolution options must match the new finding types or health checks become noisy.

### Epic Modification 8

**Artifact:** `_bmad-output/planning-artifacts/epics.md`  
**Section:** `Story 7.3: Inspectable Automation`

**OLD**

- **Then** a detailed log file is created in `logs/` with timestamp: `operation-YYYY-MM-DD-HHMMSS.log`
- **And** the log includes: operation type, files affected, changes made, duration, success/failure status
- **And** no files are modified without creating a corresponding log entry

**NEW**

- **Then** a detailed log file is created in `logs/` with timestamp: `operation-YYYY-MM-DD-HHMMSS.log`
- **And** the log includes: operation type, files affected, changes made, duration, success/failure status, and whether canonical or derived artifacts were touched
- **And** no files are modified and no derived artifacts are refreshed without creating a corresponding log entry
- **And** extraction outputs, dedup reports, and retrieval-index rebuilds are stored as reviewable artifacts rather than hidden state transitions

**Rationale**

Inspectable automation must cover derived artifacts too, not just direct file edits.

### UI/UX Modification

**Artifact:** none present  
**Section:** `N/A`

**Decision**

No UI/UX change proposal is required at this time because no UX artifact exists and the change does not introduce a new user interface. The system remains script-, markdown-, and Obsidian-workflow-driven.

## Section 5: Implementation Handoff

### Scope Classification

**Moderate**

This is a backlog and planning-artifact correction, not a product reset.

### Handoff Recipients

- **Product Owner / Course Correction owner**
  - Apply approved edits to `prd.md`, `epics.md`, and `architecture.md`
  - Update `sprint-status.yaml` after approval so story scope changes are reflected accurately
- **Architect**
  - Define the canonical-vs-derived boundary
  - Specify where derived artifacts live and how they are rebuilt
  - Define adapter rules so optional MCP exposure cannot bypass review gates
- **Developer**
  - Implement smallest-first enablers after planning approval:
    - recipe import scaffolding
    - extraction artifact generation
    - fingerprint dedup support
    - metadata-aware retrieval contract
    - health checks for extraction/index drift

### Recommended Implementation Order

1. Update planning artifacts to encode canonical-vs-derived rules.
2. Expand Story `4.3` so configuration owns recipe/extraction/dedup settings.
3. Expand Story `4.1` and `4.2` to produce reviewable extraction and dedup artifacts.
4. Expand Story `3.1` and `3.3` to consume text + metadata-aware retrieval.
5. Expand Story `6.1`, `6.2`, and `7.3` to keep the new automation inspectable and repairable.
6. Only after those guardrails exist, evaluate optional MCP exposure.

### Success Criteria

- PinkyAndTheBrain remains local-first and Markdown-canonical.
- `OB1`-inspired improvements are planned as optional derived capabilities, not a replacement core.
- Review gates remain explicit at every promotion boundary.
- Any future adapter surface is subordinate to canonical Markdown state.
- The updated stories are specific enough to implement without inventing architecture later.

### Approval Follow-Up

This proposal review updates the course-correction document only. It does **not** yet update:

- `_bmad-output/planning-artifacts/prd.md`
- `_bmad-output/planning-artifacts/epics.md`
- `_bmad-output/planning-artifacts/architecture.md`
- `sprint-status.yaml`

Those should change after explicit approval of this proposal.

## Proposed Decision Summary

Borrow `OB1`'s leverage, not its center of gravity.

That means:

- keep Markdown as the canonical knowledge layer
- add recipe-based ingestion and reviewable extraction artifacts
- add dedup fingerprints and metadata-aware retrieval as derived support layers
- keep all automation inspectable, rebuildable, and subordinate to review gates
