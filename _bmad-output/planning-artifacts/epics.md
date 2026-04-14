---
stepsCompleted: [1, 2]
inputDocuments: 
  - "_bmad-output/planning-artifacts/prd.md"
  - "_bmad-output/planning-artifacts/architecture.md"
  - "_bmad-output/planning-artifacts/prd-validation-report.md"
  - "_bmad-output/planning-artifacts/prd-validation-report-post-edit.md"
---

# PinkyAndTheBrain - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for PinkyAndTheBrain, decomposing the requirements from the PRD, UX Design if it exists, and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

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

### NonFunctional Requirements

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

### Additional Requirements

- **Starter Template Implementation**: Hybrid File-Based + obsidian-cli approach with concrete folder structure, PowerShell scripts, and templates
- **obsidian-cli Integration**: Standardized vault operations for link updates, file moves, and automation
- **Folder Structure Setup**: knowledge/inbox/, raw/, working/, wiki/, schemas/, archive/ + scripts/ + .obsidian/
- **Template System**: Inbox, working note, wiki page templates with frontmatter-driven metadata
- **Processing Pipeline Scripts**: PowerShell scripts for triage.ps1, health-check.ps1, obsidian-sync.ps1
- **BMad Agent Integration**: File-based contracts in .ai/handoffs/ for agent communication
- **Health Check Implementation**: Daily/weekly/monthly lint operations following Karpathy's pattern
- **Provenance Tracking System**: All operations preserve source metadata (NFR-006)
- **Rollback Support**: All file operations must be reversible (NFR-011)
- **Git Repository Setup**: Version control for all Markdown files with automated commits
- **Index-based Navigation**: index.md files for efficient vault navigation
- **Error Handling**: Idempotent operations with concurrent access protection

### UX Design Requirements

No UX Design document was provided (UI handled by Obsidian).

### FR Coverage Map

FR-001: Epic 1 - Low-friction knowledge capture
FR-002: Epic 4 - AI conversation import and logging  
FR-003: Epic 1 - Basic inbox triage workflow
FR-004: Epic 1 - Working notes with templates
FR-005: Epic 2 - Knowledge promotion with validation
FR-006: Epic 2 - Wiki metadata and status tracking
FR-007: Epic 3 - Cross-layer knowledge retrieval
FR-008: Epic 3 - Search diagnostics and troubleshooting
FR-009: Epic 6 - Automated health checks
FR-010: Epic 6 - Health check finding resolution
FR-011: Epic 2 - Content archiving with metadata
FR-012: Epic 5 - Sensitive content controls
FR-013: Epic 3 - AI handoff context generation
FR-014: Epic 4 - System configuration management
FR-015: Epic 5 - Existing vault import
FR-016: Epic 4 - Non-AI source capture
FR-017: Epic 5 - Project/domain separation
FR-018: Epic 6 - Offline/hook-free operation

## Epic List

### Epic 1: Basic Knowledge Lifecycle
Reno can capture knowledge, make basic triage decisions, and create working notes - completing the fundamental knowledge management workflow from input to usable state.
**FRs covered:** FR-001, FR-003, FR-004

### Epic 2: Knowledge Quality & Promotion  
Reno can promote reviewed working knowledge into verified wiki content with proper validation, metadata, and source tracking.
**FRs covered:** FR-005, FR-006, FR-011

### Epic 3: Knowledge Discovery & Retrieval
Reno can search, retrieve, and diagnose knowledge across all layers with source context and trustworthiness indicators.
**FRs covered:** FR-007, FR-008, FR-013

### Epic 4: Advanced Capture & Sources
Reno can import AI conversations, capture non-AI sources, and configure capture workflows for different input types.
**FRs covered:** FR-002, FR-016, FR-014

### Epic 5: Privacy & Project Management
Reno can handle sensitive content, separate projects/domains, and import existing vaults safely.
**FRs covered:** FR-012, FR-017, FR-015

### Epic 6: System Health & Maintenance
Reno can run health checks, repair knowledge issues, and operate offline without optional integrations.
**FRs covered:** FR-009, FR-010, FR-018

<!-- Repeat for each epic in epics_list (N = 1, 2, 3...) -->

## Epic {{N}}: {{epic_title_N}}

{{epic_goal_N}}

<!-- Repeat for each story (M = 1, 2, 3...) within epic N -->

### Story {{N}}.{{M}}: {{story_title_N_M}}

As a {{user_type}},
I want {{capability}},
So that {{value_benefit}}.

**Acceptance Criteria:**

<!-- for each AC on this story -->

**Given** {{precondition}}
**When** {{action}}
**Then** {{expected_outcome}}
**And** {{additional_criteria}}

<!-- End story repeat -->