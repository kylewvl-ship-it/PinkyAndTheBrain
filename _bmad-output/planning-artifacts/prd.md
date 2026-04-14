---
stepsCompleted:
  - step-01-init
  - step-02-discovery
  - step-02b-vision
  - step-02c-executive-summary
  - step-03-success
  - step-04-journeys
  - step-05-domain
  - step-06-innovation
  - step-07-project-type
  - step-e-01-discovery
  - step-e-02-review
  - step-e-03-edit
inputDocuments:
  - README.md
  - bulletproof_2nd_brain_system_v4.md
  - llm_wiki_2nd_brain_system_v_3.md
  - https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
  - https://github.com/coleam00/claude-memory-compiler
workflowType: 'prd'
documentCounts:
  productBriefs: 0
  research: 0
  brainstorming: 0
  projectDocs: 3
  projectContext: 0
classification:
  projectType: developer_tool
  domain: general
  complexity: low
  projectContext: brownfield
lastEdited: '2026-04-14'
editHistory:
  - date: '2026-04-14'
    changes: 'Added FR/NFR sections, clarified MVP automation phasing and out-of-scope boundaries, and added migration requirements.'
---

# Product Requirements Document - PinkyAndTheBrain

**Author:** Reno
**Date:** 2026-04-14

## Executive Summary

PinkyAndTheBrain is a local-first second-brain knowledge operating system for managing high-volume information intake across conversations, notes, research, AI sessions, and project work. It helps the user capture knowledge quickly, filter it into the right knowledge layer, remove redundancy, preserve provenance, and retrieve useful knowledge when needed.

The product is designed to support faster knowledge acquisition and recall without turning note management into a heavy process. It builds on the LLM Wiki pattern: raw sources remain the source of truth, the wiki becomes a persistent compiled knowledge layer, and an agent-facing schema defines how the system should ingest, maintain, query, and health-check the knowledge base.

The immediate product direction is Markdown-first and Obsidian-compatible. Obsidian should function as the natural reading and editing interface, while the repo provides structure, validation rules, workflow discipline, source provenance, and agent handoff contracts. Conversation capture and memory compilation patterns from `claude-memory-compiler` should inform future automation, especially around saving AI sessions into daily logs, compiling them into cross-referenced articles, and checking the knowledge base for stale claims, contradictions, or orphaned pages.

### What Makes This Special

PinkyAndTheBrain is not intended to replace Obsidian. Obsidian should remain the user-facing knowledge workspace, while PinkyAndTheBrain defines the operating system around the vault: capture flow, filtering, promotion, deduplication, provenance, staleness control, index-guided retrieval, and agent handoff quality.

The core insight is that information overload is not solved by storing more notes. It is solved by turning incoming information into trustworthy, non-duplicated, accessible knowledge with minimal friction. The product is valuable if it helps the user sift through heavy information influx, learn faster, retain more context, and keep knowledge usable over time.

### External References

- Karpathy's LLM Wiki pattern: persistent LLM-maintained Markdown wiki, raw sources as truth, schema-guided agent behavior, Obsidian as interface, index/log based navigation.
- `claude-memory-compiler`: automatic AI conversation capture, daily log compilation, concept article generation, index-guided retrieval, and lint-style knowledge health checks.

## Project Classification

PinkyAndTheBrain is a brownfield developer_tool in the general knowledge-work domain. Domain complexity is low because the product does not operate in a regulated industry, but product complexity is moderate because it must coordinate knowledge lifecycle rules, Obsidian compatibility, provenance, deduplication, retrieval, AI conversation capture, and agent workflows without becoming burdensome to maintain.

## Success Criteria

### User Success

The product succeeds when the user becomes measurably more productive in learning, retaining, and reusing knowledge. After one month of regular use, the user should be able to find previously captured knowledge faster, avoid re-processing the same information, and turn useful conversations or notes into durable knowledge without rebuilding context from scratch.

The primary user success signal is practical productivity: the system reduces the time and friction required to capture, organize, verify, and retrieve knowledge.

### Business Success

For the initial product, business success means proving that the system is useful enough to become part of the user's regular knowledge workflow. Success is not measured by revenue or broad adoption yet. It is measured by whether the system is used consistently, survives daily information influx, and remains worth maintaining.

A successful MVP should show that Obsidian-compatible knowledge management, AI conversation capture, wiki promotion, retrieval, and health checks can work together as one coherent operating system.

### Technical Success

The MVP should support automatic AI conversation capture inspired by `claude-memory-compiler`, then convert captured sessions into structured knowledge that can be promoted, searched, and checked. The system does not need to remain Markdown-only, but Markdown and Obsidian compatibility remain important constraints because the knowledge base must stay local-first, inspectable, and easy to edit.

Technical success requires the system to check itself. It should detect stale information, outdated claims, missing provenance, duplicate concepts, orphaned pages, broken links, and contradictions where possible. Health checks should protect the knowledge base from silently decaying.

### Measurable Outcomes

- The user can capture or import AI conversation knowledge into the system without manually rewriting the conversation.
- The user can promote useful information into wiki knowledge through an explicit workflow.
- The user can search or retrieve relevant stored knowledge without scanning the whole vault manually.
- The system can flag stale, redundant, unsupported, or outdated information for review.
- Obsidian remains usable as the main human-facing interface for reading and editing the knowledge base.
- The system reduces repeated context rebuilding across AI sessions and project work.

## Product Scope

### MVP - Minimum Viable Product

The MVP must include a usable knowledge lifecycle: capture, triage, working-note development, wiki promotion, search or retrieval, and knowledge health checks. It should provide enough structure to move information from captured conversations or raw notes into durable wiki pages, while preserving provenance and preventing uncontrolled duplication.

The MVP should prioritize working knowledge flow over polished UI. The core experience is: capture information, filter it, promote durable knowledge, retrieve it later, and run checks that identify stale or low-trust knowledge.

AI conversation capture should be phased. The first MVP milestone may support manual or semi-automated conversation import so the Markdown workflow can be proven. Automatic AI conversation capture is part of the MVP target, but it should not block validation of the core capture-review-promote-retrieve-health loop.

### Out of Scope for MVP

- A hosted SaaS product, multi-user account system, or revenue model.
- A required Obsidian plugin or replacement note-taking UI.
- Silent auto-promotion of AI conversation extracts into verified wiki pages.
- A database-first architecture or opaque knowledge store.
- Fully automated contradiction resolution, deduplication, or archival decisions without human review.
- Mobile, web dashboard, or polished visual analytics beyond examples needed to prove the workflow.

### Growth Features (Post-MVP)

Post-MVP growth features may include deeper Obsidian integration, richer retrieval interfaces, automated deduplication suggestions, contradiction detection across related pages, configurable review schedules, multi-agent review workflows, and dashboards for knowledge health.

### Vision (Future)

The future version should become a self-maintaining knowledge operating system that captures important conversations and information streams, compiles them into a persistent knowledge base, checks its own trustworthiness, and helps the user learn and retrieve knowledge faster across many domains.

## User Journeys

### Journey 1: Capture and Compile an AI Conversation

Reno finishes an AI conversation that produced useful project context, implementation decisions, or learning. In the current world, that knowledge risks disappearing into chat history or being remembered only vaguely. With PinkyAndTheBrain, the conversation is captured automatically or imported with minimal friction.

The system extracts useful decisions, lessons, patterns, questions, and source references into a daily log or raw capture layer. It does not immediately treat the captured content as verified knowledge. Instead, it preserves the conversation as source material and prepares candidate knowledge for review.

The value moment happens when Reno later sees the useful parts of the conversation already organized into reviewable knowledge candidates, with provenance back to the captured conversation. Reno does not need to manually rewrite the whole chat or rebuild the context from memory.

This journey reveals requirements for automatic conversation capture, raw log storage, source provenance, extraction rules, reviewable knowledge candidates, and noise filtering.

### Journey 2: Triage Messy Inbox Information

Reno captures many inputs during the day: AI responses, copied snippets, links, ideas, project notes, and half-formed questions. The inbox is intentionally low-friction, so capture does not require deciding where everything belongs immediately.

During triage, Reno reviews inbox items and decides whether each item should be deleted, archived, moved to raw, developed into a working note, or promoted toward wiki knowledge. The system helps by showing metadata, source pointers, possible duplicates, and stale or unsupported claims when available.

The value moment happens when the inbox stops being a dumping ground and becomes a controlled intake buffer. Reno can capture freely without letting unprocessed information rot into permanent clutter.

This journey reveals requirements for inbox structure, triage states, deletion/archive decisions, movement between knowledge layers, duplicate warnings, and lightweight review cadence.

### Journey 3: Promote Working Knowledge Into the Wiki

Reno has a working note that has become useful beyond the original context. It contains a developing interpretation, links to sources, unresolved questions, and maybe contradictions. The next step is to turn it into durable wiki knowledge without losing uncertainty or inventing missing facts.

The system guides the promotion workflow: check whether a canonical wiki page already exists, preserve source pointers, separate fact from inference, carry forward contradictions, add metadata, and set review triggers. If the topic overlaps with an existing wiki page, the system recommends updating, merging, or linking instead of creating a duplicate.

The value moment happens when useful thinking becomes a reusable wiki page that is clear, sourced, and easy to find later. The wiki grows only when knowledge earns a durable place.

This journey reveals requirements for promotion workflow, wiki templates, canonical page detection, metadata rules, source preservation, contradiction handling, and duplicate prevention.

### Journey 4: Retrieve Knowledge During a Later Task or AI Session

Reno starts a new task or AI session and needs relevant prior knowledge. Without the system, the user would search chat history, scan notes manually, or re-explain context from scratch.

With PinkyAndTheBrain, Reno asks a question or starts a task, and the system uses index-guided retrieval to locate relevant wiki pages, working notes, source logs, or task files. The answer should include enough context to act, but not overload the session with irrelevant material. If the retrieved information is low-confidence, stale, or unsupported, the system flags that rather than presenting it as settled truth.

The value moment happens when Reno gets useful, sourced context quickly and can continue working without rebuilding memory manually.

This journey reveals requirements for search, index-guided retrieval, context injection, confidence/staleness indicators, source links, and task/session handoff summaries.

### Journey 5: Run Health Checks and Repair Knowledge

Reno runs a health check manually or on a schedule. The system scans the knowledge base for stale pages, broken links, orphaned notes, missing metadata, duplicate concepts, unsupported claims, contradictions, and pages that have not been reviewed within their trigger window.

The system produces a focused review list instead of a vague warning dump. Reno opens a flagged item, checks the source trail, and decides whether to update the page, merge duplicates, add provenance, archive stale content, or leave the page unchanged with a note.

The value moment happens when the system catches decay before the knowledge base becomes untrustworthy. Reno can trust the wiki more because it is actively checked, not just accumulated.

This journey reveals requirements for lint-style health checks, stale claim detection, duplicate detection, broken link detection, orphan detection, metadata validation, provenance audit, and repair workflows.

### Supporting Journey: Source and Provenance Audit

Reno asks why the system believes a claim. The system shows the source trail behind the wiki statement, including the original conversation, raw note, document, or primary artifact. If the source is weak or missing, the claim is marked for repair instead of being treated as verified.

This journey reveals requirements for claim provenance, source backlinks, confidence metadata, and verification states.

### Supporting Journey: Obsidian Browsing and Editing

Reno opens the knowledge base in Obsidian to browse pages, follow backlinks, edit notes, and use the graph view. The system must tolerate normal Obsidian editing while still preserving required metadata, links, and health-check behavior.

This journey reveals requirements for Markdown compatibility, Obsidian-friendly links, vault-safe structure, editable templates, and non-invasive validation.

### Supporting Journey: Conversation Memory Failure Correction

Automatic conversation capture produces a noisy, incomplete, or misleading extraction. Reno reviews the captured log or candidate article and corrects it before promotion. The bad extraction should not silently enter verified wiki knowledge.

This journey reveals requirements for review gates, correction workflow, extraction confidence, raw transcript retention, and prevention of automatic over-promotion.

### Supporting Journey: New Topic Learning

Reno begins learning a new topic. Sources and conversations accumulate quickly. The system helps keep raw sources, working notes, and wiki pages separate while the understanding is still developing. Over time, repeated concepts become canonical wiki pages.

This journey reveals requirements for topic onboarding, working-note creation, source clustering, progressive synthesis, and eventual wiki promotion.

### Supporting Journey: Search Miss Diagnosis

Reno searches for a concept and does not find it. The system helps determine whether the knowledge was never captured, captured under a different name, left in raw/working, archived, or missing from the index. Reno can then rename, link, promote, or add the missing knowledge.

This journey reveals requirements for alias handling, index coverage, archive-aware search, missing-result diagnosis, and canonical naming.

### Supporting Journey: Agent Handoff Context Injection

Reno starts a new AI coding or knowledge session. The system injects the most relevant task context, wiki references, and prior decisions while avoiding prompt bloat. The agent receives enough memory to work safely, but still has source pointers for verification.

This journey reveals requirements for context selection, session-start summaries, task-aware retrieval, source-linked memory injection, and prompt-size control.

### Supporting Journey: Privacy and Sensitive Information Handling

Reno captures conversations and notes that may contain private context, credentials, personal reflections, or sensitive project details. Before any content is promoted or injected into future sessions, the system gives the user a way to redact, exclude, or mark information as private.

The value moment happens when Reno can use automatic capture without worrying that sensitive information will be promoted, surfaced, or reused in the wrong context.

This journey reveals requirements for redaction, exclusion rules, private metadata, do-not-promote flags, and review before reuse.

### Supporting Journey: Existing Obsidian Vault Import

Reno already has notes in Obsidian. The system scans the existing vault structure, identifies folders and note types, detects likely duplicates, and proposes how to classify content into inbox, raw, working, wiki, archive, or project-specific areas without destructive restructuring.

The value moment happens when Reno can adopt PinkyAndTheBrain without abandoning or manually reorganizing existing notes.

This journey reveals requirements for vault scanning, import preview, duplicate detection, non-destructive migration, folder mapping, and rollback planning.

### Supporting Journey: Manual Capture From Non-AI Sources

Reno captures articles, videos, docs, links, snippets, ideas, meeting notes, or book notes that did not come from an AI conversation. The system stores the source material, records provenance, and helps decide whether it belongs in raw, working, or wiki later.

This journey reveals requirements for manual capture commands, source metadata, URL/document references, intake templates, and non-conversation ingestion.

### Supporting Journey: Archive and Retirement

Reno finds a page that is stale, replaced, no longer useful, or too low-confidence for default retrieval. Instead of deleting it, the system moves it to archive with a reason and excludes it from normal retrieval while keeping it available for historical context.

This journey reveals requirements for archive states, archive reasons, retrieval exclusion, replacement links, and historical traceability.

### Supporting Journey: Contradiction Resolution

The system detects conflicting claims across wiki pages, working notes, or captured sources. Reno reviews the competing claims, follows their source trails, and decides whether to update one claim, preserve both with caveats, mark uncertainty, or archive outdated material.

This journey reveals requirements for contradiction detection, source comparison, uncertainty handling, claim status, and resolution notes.

### Supporting Journey: Backup and Portability

Reno needs confidence that the knowledge base is not trapped in a proprietary tool. The system remains local-first, file-based where practical, and inspectable. Reno can back it up, move it, version it, and recover it without relying on a single hosted service.

This journey reveals requirements for local storage, portable formats, backup guidance, version-control compatibility, and clear data ownership.

### Supporting Journey: System Configuration

Reno configures vault paths, capture sources, review cadence, health-check strictness, archive behavior, and agent context-injection rules. The system should make these settings explicit and editable without requiring code changes for normal use.

This journey reveals requirements for configuration files, documented defaults, validation of settings, and safe failure modes.

### Supporting Journey: Multi-Project or Domain Separation

Reno uses the system across different projects or learning domains. The system keeps unrelated knowledge from polluting retrieval while still allowing intentional links between domains when useful.

This journey reveals requirements for project/domain boundaries, scoped indexes, retrieval filters, cross-domain linking, and context isolation.

### Journey Requirements Summary

The journeys reveal the following capability areas:

- Automatic AI conversation capture and raw session logging.
- Manual capture for non-AI sources such as articles, videos, documents, snippets, and personal notes.
- Extraction of decisions, lessons, patterns, questions, and source references.
- Inbox triage across delete, archive, raw, working, and wiki paths.
- Explicit wiki promotion workflow with provenance and contradiction handling.
- Canonical page and duplicate concept detection.
- Search and index-guided retrieval across wiki, working notes, raw logs, archive, and task files.
- Search miss diagnosis, alias handling, and canonical naming.
- Context injection for future AI sessions and project handoffs.
- Obsidian-compatible Markdown structure, links, editing workflows, and import support.
- Existing vault scanning, import preview, and non-destructive migration.
- Knowledge health checks for stale information, missing metadata, broken links, orphaned pages, unsupported claims, contradictions, and duplicate concepts.
- Privacy controls for sensitive information, redaction, exclusion, and do-not-promote handling.
- Review gates to prevent noisy or incorrect conversation extractions from becoming durable knowledge.
- Source/provenance audit paths for claims in wiki pages.
- Archive and retirement workflows that preserve history without polluting default retrieval.
- Backup, portability, and local-first data ownership.
- Configurable paths, capture sources, review cadence, health-check strictness, and context-injection rules.
- Multi-project or domain separation to prevent irrelevant knowledge from contaminating retrieval.

## Functional Requirements

FR-001: Reno can capture low-friction inbox items from AI responses, copied snippets, links, ideas, project notes, and questions without choosing a final knowledge layer at capture time.

FR-002: Reno can import or manually record AI conversation knowledge into a raw session log while preserving source context and review status.

FR-003: Reno can triage inbox items into delete, archive, raw, working, or wiki-candidate paths with a visible disposition for each item.

FR-004: Reno can create working notes from templates that preserve status, trigger, current interpretation, evidence, connections, tensions, open questions, next moves, and source pointers.

FR-005: Reno can promote reviewed working knowledge into wiki-ready Markdown only after checking sources, confidence, contradictions, and whether a canonical wiki page already exists.

FR-006: Reno can mark wiki knowledge with status, owner, confidence, last updated, last verified, review trigger, and source list.

FR-007: Reno can search or retrieve relevant knowledge across wiki pages, working notes, raw logs, archive, and task files with enough source context to decide whether the result is trustworthy.

FR-008: Reno can diagnose search misses by checking aliases, canonical names, archived material, raw or working notes, and index coverage.

FR-009: Reno can run knowledge health checks that report stale review dates, broken links, missing metadata, unsupported claims, duplicate concepts, orphaned pages, and contradiction candidates.

FR-010: Reno can review each health-check finding and choose a repair action such as update, merge, add provenance, archive, leave unchanged with a note, or defer.

FR-011: Reno can archive stale, replaced, low-confidence, or no-longer-useful notes with an archive reason, replacement link when applicable, and default retrieval exclusion.

FR-012: Reno can mark sensitive content with redaction, exclusion, private, or do-not-promote metadata before it is promoted or injected into future AI sessions.

FR-013: Reno can generate or assemble task-aware AI handoff context from relevant task files, wiki references, prior decisions, and source pointers while avoiding unnecessary prompt bloat.

FR-014: Reno can configure vault paths, capture sources, review cadence, health-check strictness, archive behavior, and agent context-injection rules in explicit editable configuration.

FR-015: Reno can import an existing Obsidian vault through a non-destructive preview that proposes folder mapping, duplicate handling, classification into inbox/raw/working/wiki/archive, and rollback steps before any restructuring.

FR-016: Reno can capture non-AI sources such as articles, videos, docs, links, snippets, ideas, meeting notes, and book notes with provenance metadata.

FR-017: Reno can keep unrelated projects or learning domains separated during retrieval by using project or domain scope metadata and filters.

FR-018: Reno can use the system when optional Codex, Claude, VS Code, Cursor, or Obsidian hooks are missing by relying on repo files, Markdown templates, and local scripts.

## Non-Functional Requirements

NFR-001: The knowledge base must remain local-first and portable; core knowledge artifacts must be readable and editable as Markdown files without a hosted service.

NFR-002: The MVP must preserve Obsidian compatibility by using vault-safe folders, Markdown files, frontmatter where structured metadata is needed, and Obsidian-friendly links.

NFR-003: The system must not promote captured AI conversation content into verified wiki knowledge without an explicit review gate.

NFR-004: Each health-check finding must include finding type, affected file path, severity, source or rule that triggered it, and suggested repair path so Reno can decide an action without opening more than one additional context source.

NFR-005: Health-check output must list high-confidence deterministic checks before heuristic checks, with missing metadata, broken links, stale review dates, duplicate titles or aliases, unsupported claims, and orphaned pages grouped by finding type.

NFR-006: Retrieval output must include provenance or source pointers for returned wiki, working, raw, archive, or task context.

NFR-007: Archive content must be excluded from default retrieval unless the user explicitly requests archived or historical context.

NFR-008: Sensitive content controls must be inspectable in Markdown metadata or adjacent configuration so a user can verify what is private, excluded, redacted, or do-not-promote.

NFR-009: If optional Codex, Claude, VS Code, Cursor, or Obsidian hooks are missing, the system must still support capture, triage, promotion, retrieval, and health-check workflows through repo files, Markdown templates, and local scripts.

NFR-010: Automation must preserve inspectability by writing reviewable files, reports, or suggestions instead of making irreversible hidden state changes.

NFR-011: Existing vault import must be non-destructive by default and must provide a preview and rollback path before moving, renaming, or classifying existing notes.

NFR-012: Routine daily maintenance should be completable in 15 minutes for normal use by limiting required actions to inbox triage, active working-note review, and repair of health-check findings that directly affect future retrieval.

## Domain-Specific Requirements

### Compliance & Regulatory

- No domain-specific compliance regime appears required for the MVP.
- Privacy still matters because captured AI conversations and notes may include sensitive personal or project information.

### Technical Constraints

- The system should remain local-first and portable.
- Markdown and Obsidian compatibility should be preserved.
- Captured conversations should not be promoted into durable wiki knowledge without review.
- Provenance should be retained so claims can be traced back to source material.
- Health checks should detect stale, duplicate, unsupported, orphaned, or broken knowledge artifacts.
- Sensitive information should support redaction, exclusion, and do-not-promote handling.

### Integration Requirements

- Obsidian-compatible vault structure and links.
- File-based Markdown workflows.
- Future compatibility with AI conversation capture patterns inspired by `claude-memory-compiler`.

### Risk Mitigations

- Risk: noisy or misleading AI extraction enters the wiki.
  Mitigation: review gates and raw transcript/source retention.
- Risk: sensitive information gets surfaced in future sessions.
  Mitigation: privacy metadata, exclusion rules, and redaction workflow.
- Risk: duplicate or stale pages reduce trust.
  Mitigation: health checks, canonical page detection, archive/retirement workflow.

## Innovation & Novel Patterns

### Detected Innovation Areas

PinkyAndTheBrain's innovation is not a new data format or a proprietary note-taking UI. The novel pattern is the knowledge lifecycle operating model around an Obsidian-compatible vault: capture, filter, promote, retrieve, audit, and repair.

The product combines automatic AI conversation capture, source-preserving raw logs, explicit wiki promotion, provenance checks, context injection, and knowledge health checks into one local-first workflow.

### Market Context & Competitive Landscape

Existing tools often emphasize note capture, graph navigation, AI chat memory, or search separately. PinkyAndTheBrain's differentiator is treating durable knowledge as something that must earn promotion and remain inspectable over time.

The MVP should avoid competing with Obsidian as an editor. It should instead complement Obsidian by enforcing workflow discipline, provenance, and health checks around the vault.

### Validation Approach

Validate the innovation by testing whether the operating model reduces repeated context rebuilding and improves trust in stored knowledge. Useful validation signals include successful AI conversation capture, promotion of useful knowledge into sourced wiki pages, faster retrieval during later tasks, and meaningful health-check findings that lead to repairs.

### Risk Mitigation

If the full lifecycle model feels too heavy, the fallback is to keep the MVP focused on the smallest useful loop: capture, review, promote, retrieve, and run basic health checks.

If automated extraction is noisy, preserve raw logs and require review before promotion.

If health checks create too much noise, prioritize a small set of high-confidence checks first: missing metadata, broken links, stale review dates, duplicate titles or aliases, and unsupported claims.

## Developer Tool Specific Requirements

### Project-Type Overview

PinkyAndTheBrain should be treated as a local developer tool and knowledge workflow system rather than a packaged SaaS product or standalone note-taking app. The MVP should use Python as the primary runtime where automation is needed, while keeping the knowledge base Markdown-first and compatible with Obsidian.

The product should be operated through local repo scripts and Codex/BMad workflow conventions. Obsidian remains the main human-facing reading and editing interface, while VS Code, Cursor, Codex hooks, and Claude hooks may support capture, automation, and agent handoff workflows.

### Technical Architecture Considerations

The MVP should prefer simple local automation over a heavy application architecture. Python scripts should support capture, validation, indexing, promotion assistance, and health-check workflows where practical. Markdown files remain the durable storage layer, and automation should preserve inspectability rather than hiding knowledge in opaque state.

The system should avoid requiring an Obsidian plugin for the MVP. Integration should work through vault-compatible files, folders, templates, metadata, links, and scripts. Hook-based integrations for Codex, Claude, VS Code, and Cursor should be designed as optional workflow entry points rather than mandatory dependencies.

### Language Matrix

- PowerShell should be the primary automation/runtime language for MVP scripts because the MVP is Windows-local, repo-native, and already specified through PowerShell story acceptance criteria.
- Markdown remains the primary knowledge artifact format.
- YAML frontmatter should be used where structured metadata is needed.
- Python may be introduced later for parsing-heavy features if the PowerShell MVP proves the workflow and the extra runtime is justified.

### Installation Methods

- MVP usage should assume local repo scripts plus Codex/BMad workflow execution.
- The system does not need to be published as a package for MVP.
- The system should not require an Obsidian plugin for MVP adoption.
- Future packaging as a CLI or installable tool can remain a post-MVP option if the local workflow proves useful.

### API Surface

The MVP API surface should be workflow- and command-oriented rather than library-first. Candidate commands or script entry points should cover:

- Capture or import AI conversation logs.
- Create or update raw capture entries.
- Promote reviewed knowledge into wiki-ready Markdown.
- Run health checks for metadata, broken links, stale review dates, duplicates, unsupported claims, and orphaned pages.
- Search or retrieve relevant knowledge for an agent handoff.
- Generate or refresh indexes used for retrieval and navigation.

### Migration Requirements

Existing Obsidian vault import should be treated as a preview-first migration workflow rather than an automatic restructure. The workflow should scan the vault, summarize folder and note types, propose mappings into inbox, raw, working, wiki, archive, or project-specific areas, and identify likely duplicates before any files are moved.

Migration actions should be reversible. The system should produce a migration plan with source paths, target paths, classification reasons, duplicate candidates, skipped items, and rollback instructions. The user should approve the plan before any write operation affects existing notes.

Migration should preserve source material and metadata. When a note cannot be confidently classified, the system should leave it in place or route it to a review queue rather than guessing.

### Code Examples and Fixtures

The MVP should include examples that make the workflow concrete:

- Example vault pages.
- Markdown templates for inbox, raw capture, working notes, wiki pages, and archive entries.
- Example captured conversation fixtures.
- Example promotion output showing how raw conversation material becomes sourced wiki knowledge.
- Example health-check findings and repair workflow notes.

### Documentation Requirements

Documentation should include:

- README with the product purpose, workflow overview, setup assumptions, and first-run path.
- Templates documentation explaining each note type and required metadata.
- Workflow docs for capture, triage, promotion, retrieval, health checks, archive/retirement, and agent handoff.
- Hook documentation for Codex/BMad, Claude, VS Code, and Cursor integrations where relevant.

### Implementation Considerations

The implementation should stay local-first, file-based, and easy to inspect. Automation should be conservative: it may suggest promotions, repairs, merges, or exclusions, but should not silently convert noisy captures into durable wiki knowledge.

The system should be designed so that missing optional hooks do not break the core workflow. A user should be able to operate the MVP with the repo, Markdown files, Python scripts, and Obsidian-compatible editing alone.
