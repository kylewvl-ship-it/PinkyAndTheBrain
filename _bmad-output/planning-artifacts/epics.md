---
stepsCompleted: [1, 2, 3]
inputDocuments: 
  - "_bmad-output/planning-artifacts/prd.md"
  - "_bmad-output/planning-artifacts/architecture.md"
  - "_bmad-output/planning-artifacts/prd-validation-report.md"
  - "_bmad-output/planning-artifacts/prd-validation-report-post-edit.md"
epic_priority: high
implementation_order: foundation_first
document_version: "2.0"
last_validated: "2026-04-15"
---

# PinkyAndTheBrain - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for PinkyAndTheBrain, decomposing the requirements from the Product Requirements Document (PRD), UX Design specifications, and Architecture requirements into implementable stories.

**Target User**: Reno (intermediate skill level knowledge worker)  
**System Type**: Local-first knowledge management system with Obsidian compatibility  
**Implementation Approach**: PowerShell-based automation with Markdown file storage

## Table of Contents

- [Glossary](#glossary)
- [Requirements Inventory](#requirements-inventory)
- [Epic List](#epic-list)
- [Story Dependencies](#story-dependencies)
- **Epic Details:**
  - [Epic 0: System Foundation](#epic-0-system-foundation)
  - [Epic 1: Basic Knowledge Lifecycle](#epic-1-basic-knowledge-lifecycle)
  - [Epic 2: Knowledge Quality & Promotion](#epic-2-knowledge-quality--promotion)
  - [Epic 3: Knowledge Discovery & Retrieval](#epic-3-knowledge-discovery--retrieval)
  - [Epic 4: Advanced Capture & Sources](#epic-4-advanced-capture--sources)
  - [Epic 5: Privacy & Project Management](#epic-5-privacy--project-management)
  - [Epic 6: System Health & Maintenance](#epic-6-system-health--maintenance)
  - [Epic 7: System Reliability & NFR Compliance](#epic-7-system-reliability--nfr-compliance)

## Glossary

**AI Handoff Context**: Curated knowledge package prepared for AI agent consumption, limited to token constraints and excluding private content.

**Archive**: Storage layer for outdated or replaced knowledge that should not appear in default searches but remains accessible for historical reference.

**Capture**: The process of quickly saving information (from any source) into the inbox without immediate categorization.

**Disposition**: The classification decision made during triage (delete, archive, raw, working, wiki-candidate).

**FR**: Functional Requirement - specific system behaviors and capabilities.

**Health Check**: Automated analysis that identifies knowledge base issues like broken links, missing metadata, or stale content.

**Inbox**: Temporary storage for newly captured items awaiting triage and classification.

**Knowledge Layer**: One of the five organizational levels: inbox, raw, working, wiki, archive.

**NFR**: Non-Functional Requirement - system qualities like performance, security, and usability constraints.

**Promotion**: Moving content from a lower knowledge layer to a higher one (e.g., working → wiki) with validation.

**Provenance**: Source tracking metadata that identifies where knowledge originated and how it was captured.

**Raw**: Storage for imported conversations and unprocessed source material that preserves original format.

**Triage**: The review process where inbox items are assigned dispositions and moved to appropriate knowledge layers.

**Working Notes**: Structured documents for developing ideas with templates for interpretation, evidence, and connections.

**Wiki**: Verified knowledge layer containing trusted, well-sourced information ready for reference and AI handoff.

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

**Epic 0 - System Foundation:**
- Foundation for all other FRs
- Additional Requirements: Starter Template Implementation, Folder Structure Setup, Template System, Processing Pipeline Scripts, Git Repository Setup

**Epic 1 - Basic Knowledge Lifecycle:**
FR-001: Epic 1.1 - Low-friction knowledge capture with specific PowerShell commands
FR-003: Epic 1.2 - Structured inbox triage workflow with PowerShell interface
FR-004: Epic 1.3 - Working notes with templates and management commands

**Epic 2 - Knowledge Quality & Promotion:**
FR-005: Epic 2.1 - Knowledge promotion with validation
FR-006: Epic 2.2 - Wiki metadata and status tracking
FR-011: Epic 2.3 - Content archiving with metadata

**Epic 3 - Knowledge Discovery & Retrieval:**
FR-007: Epic 3.1 - Cross-layer knowledge retrieval
FR-008: Epic 3.2 - Search diagnostics and troubleshooting
FR-013: Epic 3.3 - AI handoff context generation

**Epic 4 - Advanced Capture & Sources:**
FR-002: Epic 4.1 - AI conversation import and logging  
FR-016: Epic 4.2 - Non-AI source capture
FR-014: Epic 4.3 - System configuration management

**Epic 5 - Privacy & Project Management:**
FR-012: Epic 5.1 - Sensitive content controls
FR-017: Epic 5.2 - Project/domain separation
FR-015: Epic 5.3, 5.4, 5.5 - Existing vault import (preview, execution, rollback)

**Epic 6 - System Health & Maintenance:**
FR-009: Epic 6.1 - Automated health checks
FR-010: Epic 6.2 - Health check finding resolution
FR-018: Epic 6.3 - Offline/hook-free operation

**Epic 7 - System Reliability & NFR Compliance:**
NFR-003: Epic 7.1 - AI content review gates
NFR-004, NFR-005: Epic 7.2 - Structured health check reporting
NFR-010: Epic 7.3 - Inspectable automation
NFR-012: Epic 7.4 - 15-minute daily maintenance
Error Handling: Epic 7.5 - Error handling and recovery

## Story Dependencies

### Critical Path Dependencies
```
Epic 0 (Foundation) → All Other Epics
Epic 1 (Basic Lifecycle) → Epic 2 (Quality & Promotion)
Epic 2 (Quality & Promotion) → Epic 3 (Discovery & Retrieval)
Epic 4 (Advanced Capture) → Epic 5 (Privacy & Project Management)
Epic 6 (Health & Maintenance) → Epic 7 (Reliability & NFR)
```

### Story-Level Dependencies
| Story | Depends On | Reason |
|-------|------------|---------|
| 1.2 (Inbox Triage) | 0.1, 0.2, 0.3 | Requires folder structure, templates, and scripts |
| 1.3 (Working Notes) | 0.2 (Templates) | Needs working note template system |
| 2.1 (Wiki Promotion) | 1.3 (Working Notes) | Promotes from working notes |
| 3.1 (Cross-Layer Search) | 1.1, 1.2, 2.1 | Needs content in multiple layers |
| 5.3-5.5 (Vault Import) | 0.1-0.5 (All Foundation) | Requires complete system setup |
| 6.1 (Health Checks) | All content creation stories | Needs content to validate |
| 7.4 (Daily Maintenance) | 6.1, 6.2 (Health system) | Builds on health check infrastructure |

### Implementation Phases
**Phase 1 - Foundation** (Epic 0): Complete before any other work  
**Phase 2 - Core Workflow** (Epics 1-2): Basic capture → triage → promotion cycle  
**Phase 3 - Advanced Features** (Epics 3-4): Search, AI handoff, advanced capture  
**Phase 4 - Enterprise Features** (Epics 5-7): Privacy, imports, maintenance automation

## Epic List
Reno can set up the complete PinkyAndTheBrain system from scratch with proper folder structure, templates, scripts, and configuration.
**FRs covered:** Foundation for all other FRs
**Additional Requirements covered:** Starter Template Implementation, Folder Structure Setup, Template System, Processing Pipeline Scripts, Git Repository Setup

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

### Epic 7: System Reliability & NFR Compliance
Reno can rely on the system to maintain data integrity, provide consistent performance, and meet all non-functional requirements.
**NFRs covered:** NFR-003, NFR-004, NFR-005, NFR-010, NFR-012

## Epic 0: System Foundation

Reno can set up the complete PinkyAndTheBrain system from scratch with proper folder structure, templates, scripts, and configuration.

**FRs covered:** Foundation for all other FRs  
**Additional Requirements covered:** Starter Template Implementation, Folder Structure Setup, Template System, Processing Pipeline Scripts, Git Repository Setup  
**Implementation Priority:** Critical - Must complete before any other epic

### Story 0.1: Initial System Setup and Folder Structure

**User Story:**  
As Reno,  
I want to initialize the PinkyAndTheBrain system with the complete folder structure and configuration,  
So that I have a working foundation for knowledge management.

**Acceptance Criteria:**

**Scenario: Fresh system initialization**
- **Given** I want to set up PinkyAndTheBrain in a new directory
- **When** I run the setup command `.\scripts\setup-system.ps1`
- **Then** the following folder structure is created:
```
knowledge/
├── inbox/
├── raw/
├── working/
├── wiki/
├── schemas/
└── archive/
scripts/
├── setup-system.ps1
├── capture.ps1
├── triage.ps1
├── health-check.ps1
├── search.ps1
└── obsidian-sync.ps1
templates/
├── inbox-item.md
├── working-note.md
├── wiki-page.md
└── conversation-import.md
.ai/
└── handoffs/
config/
└── pinky-config.yaml
```

**Scenario: Post-setup validation**
- **Given** the folder structure is created
- **When** the setup completes
- **Then** each folder contains an `index.md` file explaining its purpose
- **And** the `schemas/` folder contains metadata schema definitions
- **And** the `config/pinky-config.yaml` file is populated with default settings
- **And** a `.gitignore` file is created to exclude temporary files

**Scenario: Existing directory protection**
- **Given** I run setup in an existing directory with files
- **When** the setup detects existing content
- **Then** it creates a backup folder with timestamp before proceeding
- **And** it prompts me to confirm before overwriting any existing files
- **And** it provides a rollback option to restore the backup

**Error Scenarios:**
- **Given** insufficient disk space during setup
- **When** folder creation fails
- **Then** the script displays clear error message with space requirements
- **And** it cleans up any partially created folders
- **And** it exits with non-zero status code

- **Given** permission denied errors during setup
- **When** folder creation is blocked
- **Then** the script identifies which folders failed with specific permissions needed
- **And** it provides instructions for running with elevated privileges
- **And** it allows retry without recreating successful folders

### Story 0.2: Template System Creation

**User Story:**  
As Reno,  
I want standardized templates for all knowledge types with proper frontmatter schemas,  
So that all captured knowledge follows consistent metadata patterns.

**Acceptance Criteria:**

**Scenario: Template file creation**
- **Given** the template system is initialized
- **When** I examine the `templates/` folder
- **Then** I find these template files with complete frontmatter schemas:

**Inbox Item Template (`inbox-item.md`):**
```yaml
---
captured_date: {{timestamp}}
source_type: {{manual|web|conversation|document|idea}}
source_url: {{url_if_applicable}}
source_title: {{title_if_applicable}}
review_status: pending
disposition: {{inbox|raw|working|wiki|archive|delete}}
project: {{project_name_optional}}
private: false
---

# {{title}}

{{content}}

## Source Context
{{source_details}}

## Next Actions
- [ ] Review and assign disposition
```

**Working Note Template (`working-note.md`):**
```yaml
---
status: {{draft|active|promoted|archived}}
confidence: {{low|medium|high}}
last_updated: {{timestamp}}
review_trigger: {{date}}
project: {{project_name}}
domain: {{domain_name}}
source_list: []
promoted_to: {{wiki_page_link_if_promoted}}
private: false
---

# {{title}}

## Current Interpretation
{{main_understanding}}

## Evidence
{{supporting_information}}

## Connections
{{links_to_related_knowledge}}

## Tensions & Contradictions
{{conflicting_information}}

## Open Questions
{{unresolved_issues}}

## Next Moves
{{action_items}}

## Source Pointers
{{links_to_original_sources}}
```

**Wiki Page Template (`wiki-page.md`):**
```yaml
---
status: {{draft|verified|needs_review|archived}}
owner: {{author_name}}
confidence: {{low|medium|high}}
last_updated: {{timestamp}}
last_verified: {{timestamp}}
review_trigger: {{date}}
source_list: []
project: {{project_name}}
domain: {{domain_name}}
private: false
exclude_from_ai: false
---

# {{title}}

## Summary
{{concise_overview}}

## Details
{{comprehensive_information}}

## Sources
{{reference_list}}

## Related Pages
{{internal_links}}

## Confidence Notes
{{uncertainty_caveats}}
```

**Scenario: Template usage in capture**
- **Given** I create new content using templates
- **When** I use the capture commands
- **Then** the appropriate template is automatically applied
- **And** timestamp fields are auto-populated
- **And** I'm prompted to fill in required fields like title and content

**Error Scenarios:**
- **Given** a template file is corrupted or missing required frontmatter
- **When** the template is used for content creation
- **Then** the system displays a clear error identifying the missing/invalid fields
- **And** it provides a sample of correct frontmatter format
- **And** it creates content with minimal valid frontmatter as fallback

### Story 0.3: PowerShell Script Implementation

**User Story:**  
As Reno,  
I want functional PowerShell scripts for all core operations,  
So that I can perform knowledge management tasks through consistent command-line interfaces.

**Acceptance Criteria:**

**Scenario: Basic content capture**
- **Given** the scripts are installed
- **When** I run `.\scripts\capture.ps1 -Type manual -Title "My Note" -Content "Note content"`
- **Then** a new file is created in `knowledge/inbox/` using the inbox template
- **And** the filename follows the pattern `YYYY-MM-DD-HHMMSS-title.md`
- **And** all metadata fields are properly populated
- **And** the script returns the full path of the created file

**Scenario: AI conversation import**
- **Given** I want to import an AI conversation
- **When** I run `.\scripts\capture.ps1 -Type conversation -File "conversation.txt" -Service "claude"`
- **Then** the conversation is imported to `knowledge/raw/` with conversation template
- **And** the original conversation structure is preserved
- **And** metadata includes conversation_date, ai_service, and import_date

**Scenario: Inbox triage workflow**
- **Given** I want to triage inbox items
- **When** I run `.\scripts\triage.ps1`
- **Then** I see a numbered list of all inbox items with previews
- **And** I can select items by number and assign dispositions (delete/archive/raw/working/wiki)
- **And** selected items are moved to appropriate folders with updated metadata
- **And** the script handles multiple selections with comma-separated numbers

**Scenario: Knowledge search**
- **Given** I want to search across all knowledge layers
- **When** I run `.\scripts\search.ps1 -Query "search term" -Layers wiki,working`
- **Then** results are returned with layer indicators [WIKI], [WORK], etc.
- **And** each result shows filename, last modified date, and 2-line preview
- **And** results are ranked by relevance (exact title > content > metadata matches)
- **And** maximum 20 results are returned with option to see more

**Scenario: Health check execution**
- **Given** I want to run health checks
- **When** I run `.\scripts\health-check.ps1 -Type all`
- **Then** the system scans all knowledge files for issues
- **And** findings are grouped by type: Missing Metadata, Broken Links, Stale Content, Duplicates, Orphans
- **And** each finding shows file path, issue type, severity, and suggested repair action
- **And** I can run targeted checks with `-Type metadata`, `-Type links`, or `-Type stale`

**Error Scenarios:**
- **Given** invalid parameters are provided to any script
- **When** the script validates input
- **Then** it displays usage help with examples of correct syntax
- **And** it highlights the specific invalid parameter
- **And** it exits with status code 1

- **Given** a script encounters file system errors (permissions, disk full)
- **When** the error occurs during execution
- **Then** the script logs the full error to `logs/script-errors.log`
- **And** it provides a user-friendly error message with suggested solutions
- **And** it attempts to clean up any partial operations

### Story 0.4: Configuration Management System

**User Story:**  
As Reno,  
I want a comprehensive configuration system that controls all system behavior,  
So that I can customize the system to my specific workflow needs.

**Acceptance Criteria:**

**Scenario: Default configuration structure**
- **Given** the configuration system is initialized
- **When** I examine `config/pinky-config.yaml`
- **Then** I find these configurable settings with documented defaults:

```yaml
# PinkyAndTheBrain Configuration
system:
  vault_root: "./knowledge"
  script_root: "./scripts"
  template_root: "./templates"
  
folders:
  inbox: "inbox"
  raw: "raw" 
  working: "working"
  wiki: "wiki"
  archive: "archive"
  schemas: "schemas"

file_naming:
  inbox_pattern: "YYYY-MM-DD-HHMMSS-{title}"
  conversation_pattern: "YYYY-MM-DD-HHMMSS-conversation-{service}"
  working_pattern: "{title}"
  wiki_pattern: "{title}"

review_cadence:
  inbox_days: 7
  working_days: 30
  wiki_days: 90
  
health_checks:
  stale_threshold_months: 6
  min_content_length: 100
  similarity_threshold: 3
  
ai_handoff:
  max_context_tokens: 3000
  max_wiki_tokens_per_page: 500
  exclude_private: true
  
projects:
  default_project: "general"
  create_subfolders: true
  
search:
  max_results: 20
  include_archived: false
  case_sensitive: false
```

**Scenario: Configuration customization**
- **Given** I want to customize system behavior
- **When** I edit the configuration file
- **Then** all scripts respect the updated settings immediately
- **And** invalid configurations show clear error messages with suggested fixes
- **And** I can validate the configuration with `.\scripts\validate-config.ps1`

**Scenario: Project-specific settings**
- **Given** I have multiple projects with different needs
- **When** I configure project-specific settings
- **Then** I can override global settings per project
- **And** project-scoped operations only affect files tagged with that project
- **And** I can list all projects and their file counts with `.\scripts\list-projects.ps1`

**Error Scenarios:**
- **Given** invalid YAML syntax in configuration file
- **When** any script attempts to read configuration
- **Then** it displays the specific YAML parsing error with line number
- **And** it falls back to default settings with a warning
- **And** it suggests running `.\scripts\validate-config.ps1` for detailed validation

### Story 0.5: Git Integration and Version Control

**User Story:**  
As Reno,  
I want automatic version control for all knowledge files,  
So that I can track changes and recover from mistakes.

**Acceptance Criteria:**

**Scenario: Initial Git setup**
- **Given** the system is initialized with Git integration
- **When** the setup completes
- **Then** a Git repository is initialized in the root directory
- **And** a `.gitignore` file excludes temporary files and system caches
- **And** an initial commit is created with the message "Initial PinkyAndTheBrain setup"
- **And** all template files, scripts, and configuration are committed

**Scenario: Automatic change tracking**
- **Given** I perform knowledge management operations
- **When** I create, modify, or move knowledge files
- **Then** changes are automatically staged for commit
- **And** a commit is created with descriptive message: "Knowledge update: [operation] [filename]"
- **And** commits include both the changed file and any updated metadata

**Scenario: Knowledge evolution review**
- **Given** I want to review my knowledge evolution
- **When** I run `.\scripts\git-summary.ps1`
- **Then** I see a summary of recent commits grouped by operation type
- **And** I can view the history of any specific knowledge file
- **And** I can see which files have been modified but not yet committed

**Scenario: Mistake recovery**
- **Given** I make a mistake and want to recover
- **When** I run `.\scripts\rollback.ps1 -Hours 24`
- **Then** I can see all changes made in the last 24 hours
- **And** I can selectively revert specific files or operations
- **And** the rollback operation itself is committed with a clear message

**Error Scenarios:**
- **Given** Git is not installed or accessible
- **When** the system attempts Git operations
- **Then** it logs a warning about missing version control
- **And** it continues operations without Git integration
- **And** it suggests installing Git for full functionality

## Epic 1: Basic Knowledge Lifecycle

Reno can capture knowledge, make basic triage decisions, and create working notes - completing the fundamental knowledge management workflow from input to usable state.

**FRs covered:** [FR-001](#fr-001), [FR-003](#fr-003), [FR-004](#fr-004)  
**Dependencies:** [Epic 0: System Foundation](#epic-0-system-foundation)  
**Implementation Priority:** High - Core workflow functionality

### Story 1.1: Quick Knowledge Capture

**User Story:**  
As Reno,  
I want to quickly capture knowledge items using specific PowerShell commands,  
So that I don't lose important information while in flow.

**Acceptance Criteria:**

**Scenario: Basic manual capture**
- **Given** I have information to capture (AI response, snippet, link, idea, note, or question)
- **When** I run `.\scripts\capture.ps1 -Type manual -Title "My Note" -Content "Note content"`
- **Then** the item is saved to `knowledge/inbox/` with filename `YYYY-MM-DD-HHMMSS-my-note.md`
- **And** the inbox template is applied with captured_date, source_type, and review_status populated
- **And** the capture process completes in under 10 seconds
- **And** the script returns the full file path for confirmation

**Scenario: Web source capture with context**
- **Given** I capture an item with source context (URL, conversation ID, document reference)
- **When** I run `.\scripts\capture.ps1 -Type web -Title "Article" -Url "https://example.com" -Content "My notes"`
- **Then** the source metadata is preserved in frontmatter: source_url, source_title, source_type: "web"
- **And** I can trace back to the original source by opening the URL from metadata
- **And** the source context is preserved in the "Source Context" section

**Scenario: Rapid successive captures**
- **Given** I capture multiple items in quick succession
- **When** I run multiple capture commands within seconds
- **Then** each gets a unique filename with millisecond-precision timestamp
- **And** no items are lost or overwritten due to filename conflicts
- **And** the system handles concurrent captures by using file locking mechanisms

**Scenario: Clipboard and stdin capture**
- **Given** I want to capture from clipboard or stdin
- **When** I run `.\scripts\capture.ps1 -Type clipboard` or pipe content to the script
- **Then** the clipboard content or piped input is captured as the content body
- **And** I'm prompted to provide a title if not specified
- **And** the capture works even with large content (up to 10MB)

**Error Scenarios:**
- **Given** the inbox folder is not accessible or doesn't exist
- **When** I attempt to capture content
- **Then** the script displays a clear error about the missing inbox folder
- **And** it suggests running the setup script to initialize the system
- **And** it exits with status code 2

- **Given** I provide content that exceeds the 10MB limit
- **When** the capture script processes the content
- **Then** it displays a warning about content size
- **And** it offers to truncate the content or save to a separate file
- **And** it logs the oversized capture attempt

### Story 1.2: Inbox Triage Workflow

**User Story:**  
As Reno,  
I want to review inbox items using a structured PowerShell interface and assign them to specific knowledge layers,  
So that captured information gets organized appropriately.

**Acceptance Criteria:**

**Scenario: Basic triage interface**
- **Given** I have items in my `knowledge/inbox/` folder
- **When** I run `.\scripts\triage.ps1`
- **Then** I see a numbered list of all inbox items with: filename, capture date, source type, and first 100 characters of content
- **And** I can select items by number (e.g., "1,3,5" or "1-5") and assign dispositions
- **And** Available dispositions are: [D]elete, [A]rchive, [R]aw, [W]orking, Wiki-[C]andidate
- **And** The interface shows keyboard shortcuts for each action

**Scenario: Delete disposition**
- **Given** I select "D" (delete) for inbox items
- **When** the action is processed
- **Then** I'm prompted to confirm deletion with a list of items to be deleted
- **And** confirmed items are permanently removed from the file system
- **And** I receive a summary: "Deleted 3 items: [filenames]"
- **And** the deletion is logged to `logs/triage-actions.log`

**Scenario: Archive disposition**
- **Given** I select "A" (archive) for inbox items
- **When** the action is processed
- **Then** items are moved to `knowledge/archive/` folder
- **And** frontmatter is updated with: disposition: "archived", archive_date, archive_reason: "triaged_from_inbox"
- **And** archived items are excluded from default search results
- **And** I can optionally provide a custom archive reason

**Scenario: Promote to knowledge layers**
- **Given** I select "R", "W", or "C" for inbox items
- **When** the action is processed
- **Then** items are moved to `knowledge/raw/`, `knowledge/working/`, or remain in inbox with wiki-candidate flag
- **And** frontmatter disposition field is updated accordingly
- **And** original capture metadata (captured_date, source_type, etc.) is preserved
- **And** moved files retain their original filename structure

**Scenario: Batch processing with filters**
- **Given** I want to batch process similar items
- **When** I use filters like `.\scripts\triage.ps1 -SourceType web` or `.\scripts\triage.ps1 -OlderThan 7`
- **Then** only matching items are shown for triage
- **And** I can apply the same disposition to all filtered items with "all" command
- **And** filters can be combined: `-SourceType conversation -OlderThan 3`

**Error Scenarios:**
- **Given** I attempt to delete items but lack file system permissions
- **When** the deletion is processed
- **Then** the script identifies which files couldn't be deleted with specific permission errors
- **And** it continues processing other items that can be deleted
- **And** it provides instructions for resolving permission issues

- **Given** the target folder for a disposition doesn't exist
- **When** I try to move items to that folder
- **Then** the script creates the missing folder with appropriate permissions
- **And** it logs the folder creation action
- **And** it continues with the move operation

### Story 1.3: Working Note Creation and Management

**User Story:**  
As Reno,  
I want to create structured working notes using templates and PowerShell commands,  
So that I can develop ideas with proper metadata and source tracking.

**Acceptance Criteria:**

**Scenario: New working note from scratch**
- **Given** I want to create a new working note from scratch
- **When** I run `.\scripts\create-working-note.ps1 -Title "My Topic" -Project "research"`
- **Then** a new file is created in `knowledge/working/` using the working-note template
- **And** the filename is `my-topic.md` (title converted to kebab-case)
- **And** frontmatter includes: status: "draft", confidence: "low", last_updated: timestamp, project: "research"
- **And** all template sections are present: Current Interpretation, Evidence, Connections, Tensions, Open Questions, Next Moves, Source Pointers

**Scenario: Working note from existing content**
- **Given** I create a working note from an inbox or raw item
- **When** I run `.\scripts\promote-to-working.ps1 -SourceFile "knowledge/inbox/my-item.md" -Title "Working Topic"`
- **Then** a new working note is generated with the source item's content in the Evidence section
- **And** the source item's metadata is automatically linked in the Source Pointers section
- **And** the original item is marked with promoted_to: "knowledge/working/working-topic.md"
- **And** the working note includes source_list: ["knowledge/inbox/my-item.md"] in frontmatter

**Scenario: Automatic metadata management**
- **Given** I have a working note with required metadata fields
- **When** I save changes to the note (either manually or through scripts)
- **Then** the last_updated timestamp is automatically updated by a file watcher or save hook
- **And** the review_trigger is recalculated based on configured review cadence (default 30 days)
- **And** metadata validation ensures required fields (status, confidence, last_updated) are present
- **And** invalid metadata values trigger warnings with suggested corrections

**Scenario: Working note evolution tracking**
- **Given** I update a working note over time
- **When** I make changes to any section
- **Then** I can track the evolution through Git history with automatic commits
- **And** the structured sections help me organize: new evidence, changed interpretations, resolved questions
- **And** I can run `.\scripts\working-note-summary.ps1 -File "my-topic.md"` to see a change summary
- **And** overdue review triggers (past review_trigger date) are flagged in health checks

**Scenario: Working note management overview**
- **Given** I want to manage multiple working notes
- **When** I run `.\scripts\list-working-notes.ps1`
- **Then** I see all working notes with: title, status, confidence, last_updated, days until review
- **And** I can filter by status: `.\scripts\list-working-notes.ps1 -Status active`
- **And** I can sort by various fields: `-SortBy last_updated`, `-SortBy confidence`
- **And** overdue notes (past review_trigger) are highlighted in red

**Error Scenarios:**
- **Given** I try to create a working note with a title that already exists
- **When** the creation script runs
- **Then** it suggests alternative titles with numbered suffixes
- **And** it asks if I want to open the existing note instead
- **And** it prevents accidental overwrites of existing content

- **Given** the source file for promotion is corrupted or has invalid frontmatter
- **When** I run the promotion script
- **Then** it extracts whatever content is readable
- **And** it creates the working note with a warning about source issues
- **And** it logs the corruption details for manual review

## Epic 2: Knowledge Quality & Promotion

Reno can promote reviewed working knowledge into verified wiki content with proper validation, metadata, and source tracking.

**FRs covered:** [FR-005](#fr-005), [FR-006](#fr-006), [FR-011](#fr-011)  
**Dependencies:** [Epic 1: Basic Knowledge Lifecycle](#epic-1-basic-knowledge-lifecycle)  
**Implementation Priority:** High - Quality assurance for knowledge base

### Story 2.1: Wiki Promotion Workflow

**User Story:**  
As Reno,  
I want to promote reviewed working knowledge into wiki-ready Markdown,  
So that valuable insights become permanent, searchable knowledge.

**Acceptance Criteria:**

**Scenario: Duplicate detection during promotion**
- **Given** I have a working note that I want to promote to wiki
- **When** I initiate the promotion workflow
- **Then** the system checks if a canonical wiki page already exists for this topic
- **And** I am warned if potential duplicates are found
- **And** I can choose to update existing page, merge content, or create new page

**Scenario: Successful wiki promotion**
- **Given** I proceed with wiki promotion after duplicate check
- **When** the promotion is processed
- **Then** a new wiki page is created with proper wiki template structure
- **And** all source pointers from the working note are preserved
- **And** the working note is marked as "promoted" with a link to the wiki page

**Scenario: Handling contradictions and uncertainties**
- **Given** I promote content that contains contradictions or uncertainties
- **When** the wiki page is created
- **Then** contradictions are clearly marked and preserved rather than resolved automatically
- **And** uncertainty levels are indicated in the content
- **And** competing claims reference their respective sources

**Scenario: Source validation requirement**
- **Given** I promote working knowledge with insufficient sources
- **When** the promotion workflow runs
- **Then** I am prompted to add missing provenance before completion
- **And** the promotion can be saved as draft until sources are added
- **And** unsupported claims are flagged for review

**Error Scenarios:**
- **Given** the working note has corrupted or missing frontmatter
- **When** I attempt promotion
- **Then** the system identifies specific missing metadata fields
- **And** it provides a template to fix the frontmatter
- **And** it prevents promotion until required fields are present

- **Given** the wiki folder is not accessible during promotion
- **When** the promotion attempts to create the wiki page
- **Then** it displays a clear error about folder permissions
- **And** it suggests checking folder permissions and disk space
- **And** it preserves the promotion attempt for retry

### Story 2.2: Wiki Metadata Management

**User Story:**  
As Reno,  
I want to mark wiki knowledge with comprehensive metadata,  
So that I can track status, confidence, sources, and review schedules.

**Acceptance Criteria:**

**Given** I create or update a wiki page
**When** the page is saved
**Then** the frontmatter includes: status, owner, confidence level, last updated, last verified, review trigger, and source list
**And** all metadata follows the standardized wiki schema
**And** timestamps are automatically managed by the system

**Given** I set a confidence level for wiki content
**When** the metadata is processed
**Then** the confidence level is visible in searches and retrieval
**And** low-confidence content is flagged appropriately
**And** confidence affects how the content appears in AI handoff contexts

**Given** I configure review triggers for wiki pages
**When** the review date arrives
**Then** the page appears in my review queue
**And** I can update the content, extend the review period, or mark as verified
**And** overdue reviews are highlighted in health checks

**Given** I update source lists for wiki pages
**When** sources are modified
**Then** the source metadata is validated for accessibility
**And** broken or missing sources trigger warnings
**And** source changes are tracked in the page history

### Story 2.3: Content Archival System

As Reno,
I want to archive stale or replaced content with proper metadata,
So that outdated information doesn't pollute active knowledge while remaining accessible for history.

**Acceptance Criteria:**

**Given** I identify content that should be archived (stale, replaced, low-confidence, or no longer useful)
**When** I initiate the archive workflow
**Then** I must provide an archive reason from predefined categories
**And** I can optionally specify a replacement link if newer content exists
**And** the content is moved to the archive folder with archive metadata

**Given** content is archived with a replacement link
**When** the archival is processed
**Then** any existing links to the archived content show archive status
**And** readers are automatically redirected or warned about the archived status
**And** the replacement content is suggested when available

**Given** I search or retrieve knowledge
**When** the system processes my query
**Then** archived content is excluded from default results
**And** I can explicitly request archived/historical context if needed
**And** archive status is clearly indicated when archived content appears

**Given** I archive content that other pages reference
**When** the archival is processed
**Then** I am shown all pages that link to the content being archived
**And** I can choose to update those references or leave them with archive warnings
**And** orphaned references are tracked for future cleanup

## Epic 3: Knowledge Discovery & Retrieval

Reno can search, retrieve, and diagnose knowledge across all layers with source context and trustworthiness indicators.

### Story 3.1: Cross-Layer Knowledge Search

As Reno,
I want to search across wiki pages, working notes, raw logs, archive, and task files,
So that I can find relevant knowledge regardless of where it's stored.

**Acceptance Criteria:**

**Given** I perform a text search query
**When** the search is executed
**Then** results are returned from all knowledge layers using file content and metadata matching
**And** results are ranked by: exact title match > exact content match > partial content match > metadata match
**And** each result shows: filename, knowledge layer, last modified date, and 2-line preview
**And** maximum 20 results are returned to avoid overwhelming output

**Given** search results include content from different knowledge layers
**When** results are displayed
**Then** each result is prefixed with layer indicator: [WIKI], [WORK], [RAW], [ARCH], [TASK]
**And** wiki results show confidence level if available in frontmatter
**And** archived results show archive date and reason
**And** working notes show current status from frontmatter

**Given** I want to filter search results by knowledge layer
**When** I specify layer filters (--wiki, --working, --raw, --archive, --tasks)
**Then** search only returns results from specified layers
**And** I can combine multiple layer filters (e.g., --wiki --working)
**And** archived content is excluded by default unless --archive is specified

**Given** I click on a search result
**When** the result is opened
**Then** I can see the full content with search terms highlighted
**And** source metadata is displayed (original capture source, promotion history)
**And** broken internal links are flagged with [BROKEN LINK] indicators

### Story 3.2: Search Diagnostics & Troubleshooting

As Reno,
I want to diagnose search misses with basic checks,
So that I can understand why expected content isn't found.

**Acceptance Criteria:**

**Given** I search for something and get fewer than 3 results
**When** I run search diagnostics (--diagnose flag)
**Then** the system performs case-insensitive search across all layers
**And** it searches for partial filename matches in all folders
**And** it reports total file count per knowledge layer for context

**Given** search diagnostics find no exact matches
**When** the diagnostic runs
**Then** it suggests checking archived content with --archive flag
**And** it shows if similar filenames exist (edit distance < 3 characters)
**And** it reports if the search term appears in any frontmatter metadata

**Given** I expect content to exist but can't find it
**When** I run diagnostics with a specific term
**Then** the system shows which folders were searched and file counts
**And** it indicates if any files have missing or corrupted frontmatter
**And** it suggests alternative search terms based on similar existing filenames

**Given** diagnostics reveal potential matches
**When** the analysis completes
**Then** I get specific actionable suggestions: "Check archived content", "Try filename search", "Check raw folder"
**And** each suggestion includes the exact command to run
**And** no machine learning or complex inference is required

### Story 3.3: AI Handoff Context Generation

As Reno,
I want to generate focused context packages for AI sessions,
So that agents receive relevant background within token limits.

**Acceptance Criteria:**

**Given** I request context generation for a specific topic or task
**When** I provide keywords or task description
**Then** the system searches for relevant wiki pages and working notes using keyword matching
**And** it prioritizes wiki content over working notes over raw content
**And** the total context package is limited to 3000 tokens maximum

**Given** multiple relevant files are found for context generation
**When** the context package is assembled
**Then** wiki pages are included in full if under 500 tokens each
**And** working notes are included as summaries (first paragraph + key points)
**And** source file paths are included for each piece of content
**And** contradictory information is flagged with [CONFLICTING INFO] markers

**Given** I want to inject context into an AI session
**When** the handoff context is generated
**Then** it outputs a structured markdown file with: task context, relevant wiki excerpts, working note summaries, and source references
**And** it excludes any files marked with "private: true" in frontmatter
**And** it includes a token count and source file list at the end

**Given** I generate context for a specific project
**When** the system selects content
**Then** it only includes files with matching project tags in frontmatter
**And** it respects folder-based project boundaries (project-specific subfolders)
**And** cross-project references are excluded unless explicitly tagged as shared

## Epic 4: Advanced Capture & Sources

Reno can import AI conversations, capture non-AI sources, and configure capture workflows for different input types.

### Story 4.1: AI Conversation Import

As Reno,
I want to import AI conversation logs into structured raw sessions,
So that valuable AI interactions are preserved with proper context and metadata.

**Acceptance Criteria:**

**Given** I have an AI conversation file or text to import
**When** I use the conversation import command
**Then** the conversation is saved to the raw folder with timestamp and filename format: YYYY-MM-DD-HH-MM-conversation-[service].md
**And** the import preserves the exact conversation text without modification
**And** the frontmatter includes: conversation_date, ai_service, import_date, and review_status: "pending"

**Given** I import a conversation with mixed content (text, code, links)
**When** the import is processed
**Then** code blocks are preserved with proper markdown formatting
**And** URLs are preserved as clickable links
**And** the conversation structure (user/assistant turns) is maintained with clear separators

**Given** I import conversations from different sources (copy-paste, file upload, API export)
**When** each conversation is imported
**Then** the import method is recorded in metadata for troubleshooting
**And** the system handles plain text, markdown, and JSON conversation formats
**And** malformed imports are saved with error notes rather than rejected

**Given** I want to process imported conversations for promotion
**When** I review the raw conversation files
**Then** I can manually select and copy sections for promotion to working notes
**And** the original conversation file remains unchanged as source material
**And** any promoted content includes a link back to the source conversation file

### Story 4.2: Non-AI Source Capture

As Reno,
I want to capture articles, videos, documents, and other non-AI sources with provenance metadata,
So that all knowledge inputs are tracked regardless of origin.

**Acceptance Criteria:**

**Given** I want to capture content from a web source
**When** I provide a URL and use the source capture command
**Then** the system saves the URL, page title, and capture date to frontmatter
**And** I manually add my own summary, quotes, or notes in the content body
**And** the captured content is saved to inbox with source_type: "web" in metadata

**Given** I capture content from offline sources (books, meetings, videos)
**When** I create the capture entry
**Then** I fill out a template with fields: source_type, title, author/participants, date, and my_notes
**And** the system provides templates for common source types (book, meeting, video, article, idea)
**And** all fields are optional except source_type and my_notes

**Given** I capture content that contains sensitive information
**When** I create or edit the capture
**Then** I can set "private: true" in the frontmatter
**And** private content shows [PRIVATE] indicator in search results
**And** private content is excluded from AI handoff context generation by default

**Given** I capture content with incomplete or missing source information
**When** the capture is saved
**Then** the system accepts partial metadata without validation errors
**And** missing source information is marked as "unknown" rather than causing failures
**And** I can update source information later without recreating the capture

### Story 4.3: Capture Configuration Management

As Reno,
I want to configure capture sources, folder paths, and processing rules,
So that the system adapts to my specific workflow and input patterns.

**Acceptance Criteria:**

**Given** I want to customize folder locations and file naming
**When** I edit the configuration file
**Then** I can specify custom paths for inbox, raw, working, wiki, and archive folders
**And** I can set filename patterns with variables like {date}, {time}, {source_type}
**And** invalid path configurations show clear error messages with suggested fixes

**Given** I have multiple projects that need separation
**When** I configure project-specific settings
**Then** I can define project tags that create subfolders (e.g., project: "work" → inbox/work/)
**And** I can set default project tags for different capture types
**And** captures without project tags go to the root folders as fallback

**Given** I want to set up review schedules and reminders
**When** I configure review cadences
**Then** I can set review intervals in days (e.g., inbox: 7, working: 30, wiki: 90)
**And** overdue items are flagged in health check reports with specific days overdue
**And** I can disable review reminders for specific folders or content types

**Given** I want to configure metadata templates for different source types
**When** I set up source type templates
**Then** I can define required and optional fields for each source type (book, meeting, web, etc.)
**And** the capture interface shows the appropriate template based on selected source type
**And** I can add custom source types with their own metadata schemas

## Epic 5: Privacy & Project Management

Reno can handle sensitive content, separate projects/domains, and import existing vaults safely.

### Story 5.1: Sensitive Content Controls

As Reno,
I want to mark and control sensitive content with redaction and exclusion metadata,
So that private information doesn't leak into AI sessions or shared contexts.

**Acceptance Criteria:**

**Given** I capture or create content that contains sensitive information
**When** I edit the content's frontmatter
**Then** I can set "private: true" to mark the entire file as private
**And** I can set "exclude_from_ai: true" to prevent AI handoff inclusion
**And** I can add "redacted_sections: []" to list specific content areas that need redaction

**Given** I have content marked as private
**When** the content appears in search results
**Then** it shows a [PRIVATE] indicator next to the filename
**And** the content preview is limited to the title and metadata only
**And** I must explicitly open private files to see their full content

**Given** I generate AI handoff context
**When** the system selects relevant content
**Then** files with "private: true" are automatically excluded
**And** files with "exclude_from_ai: true" are excluded from context packages
**And** redacted sections are replaced with [REDACTED] placeholders in any included content

**Given** I want to review all sensitive content in my vault
**When** I run a privacy audit command
**Then** I get a list of all files marked as private or excluded from AI
**And** I can see which files have redacted sections
**And** I can update privacy settings for multiple files at once

### Story 5.2: Project and Domain Separation

As Reno,
I want to separate unrelated projects and learning domains during retrieval,
So that irrelevant knowledge doesn't contaminate my current work context.

**Acceptance Criteria:**

**Given** I want to organize content by project or domain
**When** I create or edit any knowledge file
**Then** I can set "project: [project_name]" in the frontmatter
**And** I can set "domain: [domain_name]" for broader topic categorization
**And** I can assign multiple projects or domains using arrays: ["project1", "project2"]

**Given** I perform a search with project scope
**When** I use project filters (--project work, --project personal)
**Then** search results only include files tagged with matching project metadata
**And** I can combine multiple project filters (--project work --project research)
**And** files without project tags are excluded from scoped searches

**Given** I generate AI handoff context for a specific project
**When** I specify the project context
**Then** only files with matching project tags are included
**And** cross-project references are excluded unless explicitly tagged as "shared: true"
**And** the context package shows which project scope was used

**Given** I want to see my project organization
**When** I run a project overview command
**Then** I get a list of all projects with file counts
**And** I can see which files are untagged (no project assignment)
**And** I can bulk-assign project tags to untagged files by folder or pattern

### Story 5.3: Vault Import Preview and Analysis

As Reno,
I want to preview how my existing Obsidian vault would be imported before making any changes,
So that I can understand the impact and make informed decisions.

**Acceptance Criteria:**

**Given** I have an existing Obsidian vault to import
**When** I run `.\scripts\import-preview.ps1 -SourceVault "C:\MyVault"`
**Then** the system scans all markdown files in the source vault recursively
**And** it analyzes folder structure and identifies note types based on: filename patterns, frontmatter, content length, link density
**And** it generates a preview report showing proposed classification into inbox/raw/working/wiki/archive
**And** the preview shows file counts per category and lists any files that couldn't be classified

**Given** the import preview identifies potential duplicates
**When** the analysis completes
**Then** I see a "Potential Duplicates" section with files that might duplicate existing PinkyAndTheBrain content
**And** each duplicate shows similarity reasons: exact title match, content overlap percentage, similar filename
**And** I can choose resolution strategies: skip, rename with suffix, merge content, or import as separate file
**And** the preview estimates total import time and disk space requirements

**Given** I want to customize the import classification
**When** I review the preview report
**Then** I can override classifications for specific files or folders
**And** I can create custom mapping rules: "Daily Notes" folder → raw, "MOCs" folder → wiki, "Templates" folder → skip
**And** I can save mapping rules as a profile for future imports
**And** the preview updates in real-time as I adjust classifications

### Story 5.4: Vault Import Execution

As Reno,
I want to execute the vault import with my chosen settings and safeguards,
So that I can safely bring my existing knowledge into PinkyAndTheBrain.

**Acceptance Criteria:**

**Given** I've reviewed the import preview and want to proceed
**When** I run `.\scripts\execute-import.ps1 -PreviewFile "import-preview-20240414.json"`
**Then** files are copied (not moved) from source vault to appropriate PinkyAndTheBrain folders
**And** original vault remains completely unchanged as backup
**And** imported files get "imported_from: [source_path]" and "import_date: [timestamp]" metadata
**And** a detailed import log is created showing every file operation

**Given** imported files have existing frontmatter or metadata
**When** files are processed during import
**Then** existing frontmatter is preserved and merged with PinkyAndTheBrain required metadata
**And** conflicting metadata fields (e.g., existing "status" vs. required "status") show warnings in import log
**And** I can set default values for missing required metadata: default confidence: "medium", default project: "imported"
**And** invalid or corrupted frontmatter is flagged but doesn't stop the import

**Given** I import a vault with custom folder structures
**When** the import processes different folder types
**Then** folder mappings from the preview are applied consistently
**And** unmapped folders create project-specific subfolders (e.g., source "Work" → files tagged with project: "work")
**And** nested folder structures are flattened or preserved based on configuration
**And** folder names are sanitized to match PinkyAndTheBrain naming conventions

**Given** the import encounters errors or conflicts
**When** issues arise during execution
**Then** the import continues processing other files rather than stopping completely
**And** all errors are logged with specific file paths and error descriptions
**And** I can resume a failed import from where it left off
**And** partial imports can be rolled back if needed

### Story 5.5: Import Rollback and Recovery

As Reno,
I want to rollback a vault import that didn't work as expected,
So that I can return to a clean state and try again with different settings.

**Acceptance Criteria:**

**Given** I want to rollback an import that completed within the last 7 days
**When** I run `.\scripts\rollback-import.ps1 -ImportId "import-20240414-143022"`
**Then** I see a summary of what will be removed: file count per folder, total size, import date
**And** I must confirm the rollback with "YES" (case-sensitive) to prevent accidental execution
**And** all imported files are removed from PinkyAndTheBrain folders based on import_date and imported_from metadata
**And** a rollback log is created showing every file removal operation

**Given** I confirm the rollback operation
**When** the rollback executes
**Then** only files with matching import metadata are removed (no risk to existing PinkyAndTheBrain content)
**And** I get a confirmation summary: "Removed 247 files imported on 2024-04-14"
**And** the system returns to pre-import state with no data loss
**And** the rollback operation itself is logged and can be reviewed later

**Given** some imported files have been modified since import
**When** the rollback processes these files
**Then** I'm warned about files that have been changed since import
**And** I can choose to: remove anyway, keep modified files, or backup modified files before removal
**And** modified files are identified by comparing last_updated timestamp with import_date
**And** the rollback preserves any work done on imported content if requested

**Given** I want to retry import after rollback
**When** I run a new import preview on the same source vault
**Then** the system doesn't show the rolled-back files as duplicates
**And** I can apply lessons learned from the first import attempt
**And** previous import logs and rollback logs are preserved for reference
**And** I can use different classification rules or folder mappings

## Epic 6: System Health & Maintenance

Reno can run health checks, repair knowledge issues, and operate offline without optional integrations.

### Story 6.1: Automated Health Checks

As Reno,
I want to run comprehensive health checks that detect knowledge base issues,
So that I can maintain trust and quality in my stored knowledge over time.

**Acceptance Criteria:**

**Given** I run a health check on my knowledge base
**When** the system scans all knowledge files
**Then** it checks for missing required metadata (status, last_updated, confidence) in wiki and working files
**And** it identifies broken internal links using [[link]] and [link](path) formats
**And** it finds orphaned files (no incoming links from other knowledge files)
**And** it detects stale review dates based on configured review intervals

**Given** the health check analyzes content quality
**When** it processes wiki and working notes
**Then** it flags files with no source references in frontmatter
**And** it identifies potential duplicate titles or very similar filenames (edit distance < 3)
**And** it finds files that haven't been updated in over 6 months
**And** it reports files with empty or minimal content (less than 100 characters)

**Given** health check results are generated
**When** the scan completes
**Then** findings are grouped by type: Missing Metadata, Broken Links, Stale Content, Duplicates, Orphans
**And** each finding shows: file path, issue type, severity (high/medium/low), and suggested repair action
**And** high-confidence deterministic issues (broken links, missing metadata) are listed before heuristic issues
**And** total counts are provided for each finding type

**Given** I want to focus on specific health check areas
**When** I run targeted health checks
**Then** I can check only metadata issues with --metadata flag
**And** I can check only link integrity with --links flag
**And** I can check only staleness with --stale flag
**And** I can exclude archived content from health checks by default

### Story 6.2: Health Check Finding Resolution

As Reno,
I want to review and resolve health check findings with guided repair actions,
So that I can systematically improve my knowledge base quality.

**Acceptance Criteria:**

**Given** I have health check findings to resolve
**When** I review a specific finding
**Then** I see the full context: affected file, issue description, severity, and 2-3 suggested repair actions
**And** I can choose from actions like: update metadata, fix link, merge duplicate, archive file, or defer
**And** each action shows exactly what will be changed before I confirm

**Given** I choose to fix a broken link
**When** I select the repair action
**Then** the system shows me potential link targets based on filename similarity
**And** I can choose the correct target or mark the link as intentionally broken
**And** the fix is applied immediately with confirmation of the change

**Given** I want to resolve multiple similar findings at once
**When** I select batch operations
**Then** I can apply the same fix to all files missing the same metadata field
**And** I can bulk-archive all files that haven't been updated in over a year
**And** I can batch-update review dates for files in the same project or domain

**Given** I defer a finding for later resolution
**When** I mark it as deferred
**Then** the finding is excluded from future health check reports for 30 days
**And** I can add a note explaining why it was deferred
**And** deferred findings appear in a separate "Deferred Issues" section

### Story 6.3: Offline and Hook-Free Operation

As Reno,
I want the system to work fully without optional integrations or external dependencies,
So that I can maintain my knowledge workflow even when tools are unavailable.

**Acceptance Criteria:**

**Given** I don't have Obsidian installed or available
**When** I use PinkyAndTheBrain commands
**Then** all capture, triage, promotion, search, and health check functions work through file operations and scripts
**And** I can edit files directly in any text editor while maintaining metadata integrity
**And** Link updates and file moves are handled through PowerShell scripts instead of Obsidian API

**Given** I don't have AI integrations (Claude, GPT, etc.) available
**When** I perform knowledge management tasks
**Then** I can still capture, organize, search, and maintain knowledge manually
**And** AI handoff context generation creates static markdown files I can copy-paste into any AI interface
**And** All templates and workflows remain functional without AI automation

**Given** I work in an environment without internet access
**When** I use the knowledge management system
**Then** all core functions (capture, triage, promotion, search, health checks) work offline
**And** Source metadata can reference local files, offline documents, or "offline source" placeholders
**And** Health checks work on local file system without external validation

**Given** I need to use the system on a different computer or setup
**When** I copy my knowledge base to a new environment
**Then** all markdown files remain readable and editable in any text editor
**And** PowerShell scripts work on any Windows system with PowerShell 5.1+
### Epic 7: System Reliability & NFR Compliance
Reno can rely on the system to maintain data integrity, provide consistent performance, and meet all non-functional requirements.
**NFRs covered:** NFR-003, NFR-004, NFR-005, NFR-010, NFR-012

## Epic 7: System Reliability & NFR Compliance

Reno can rely on the system to maintain data integrity, provide consistent performance, and meet all non-functional requirements.

### Story 7.1: AI Content Review Gates (NFR-003)

As Reno,
I want explicit review gates that prevent AI conversation content from being automatically promoted to verified wiki knowledge,
So that I maintain control over what becomes trusted knowledge.

**Acceptance Criteria:**

**Given** I import an AI conversation using `.\scripts\capture.ps1 -Type conversation`
**When** the conversation is processed
**Then** it's saved to `knowledge/raw/` with review_status: "pending" and promotion_blocked: true
**And** the content cannot be promoted to wiki without explicit review and approval
**And** any attempt to promote shows a warning: "AI content requires manual review before wiki promotion"

**Given** I want to promote AI conversation content to working notes
**When** I run `.\scripts\promote-to-working.ps1 -SourceFile "raw/conversation.md"`
**Then** I must explicitly confirm with `--confirm-ai-content` flag
**And** the working note is marked with ai_derived: true in frontmatter
**And** I'm prompted to review and validate the content before saving

**Given** I try to promote AI-derived working notes to wiki
**When** I run the wiki promotion workflow
**Then** I see a review checklist: "Sources verified?", "Claims fact-checked?", "Contradictions noted?"
**And** I must check all items before promotion can proceed
**And** the wiki page includes ai_content_reviewed: true and review_date in metadata

### Story 7.2: Structured Health Check Reporting (NFR-004, NFR-005)

As Reno,
I want health check findings to follow a consistent, actionable format with proper prioritization,
So that I can efficiently resolve issues without opening multiple context sources.

**Acceptance Criteria:**

**Given** I run `.\scripts\health-check.ps1`
**When** the health check completes
**Then** each finding includes exactly these fields: finding_type, file_path, severity (high/medium/low), rule_triggered, suggested_repair_action
**And** findings are grouped by type in this order: Missing Metadata, Broken Links, Stale Review Dates, Duplicate Titles, Unsupported Claims, Orphaned Pages
**And** high-confidence deterministic checks (broken links, missing required metadata) appear before heuristic checks (potential duplicates, stale content)

**Given** health check findings are displayed
**When** I review the output
**Then** each finding shows a one-line summary and a specific repair command
**And** I can execute the suggested repair with copy-paste: `.\scripts\fix-metadata.ps1 -File "path" -Field "confidence" -Value "medium"`
**And** findings include context: "File has no confidence level (required for wiki pages)"
**And** total counts are provided: "Found 12 issues: 3 high, 7 medium, 2 low severity"

**Given** I want to focus on specific finding types
**When** I run targeted health checks
**Then** `.\scripts\health-check.ps1 -Type metadata` shows only metadata issues with specific missing fields
**And** `.\scripts\health-check.ps1 -Type links` shows broken links with suggested target files
**And** `.\scripts\health-check.ps1 -Type stale` shows overdue reviews with days overdue and suggested review dates

### Story 7.3: Inspectable Automation (NFR-010)

As Reno,
I want all automated operations to create reviewable files and reports instead of making hidden changes,
So that I can understand and verify what the system has done.

**Acceptance Criteria:**

**Given** any automated operation runs (triage, promotion, health checks, imports)
**When** the operation completes
**Then** a detailed log file is created in `logs/` with timestamp: `operation-YYYY-MM-DD-HHMMSS.log`
**And** the log includes: operation type, files affected, changes made, duration, success/failure status
**And** no files are modified without creating a corresponding log entry

**Given** automated metadata updates occur (timestamps, review triggers, etc.)
**When** files are modified
**Then** the changes are staged for Git commit with descriptive messages
**And** I can review staged changes with `.\scripts\review-pending-changes.ps1`
**And** I can approve or reject automated changes before they're committed
**And** rejected changes are rolled back and logged

**Given** I want to understand what automation has done
**When** I run `.\scripts\automation-summary.ps1 -Days 7`
**Then** I see a summary of all automated operations in the last 7 days
**And** each operation shows: type, files affected, success rate, any errors or warnings
**And** I can drill down into specific operations to see detailed logs
**And** suspicious patterns (many failures, unexpected file changes) are highlighted

### Story 7.4: 15-Minute Daily Maintenance (NFR-012)

As Reno,
I want daily maintenance tasks to be completable within 15 minutes,
So that knowledge management doesn't become a burden.

**Acceptance Criteria:**

**Given** I start my daily maintenance routine
**When** I run `.\scripts\daily-maintenance.ps1`
**Then** the script shows a prioritized task list with estimated time for each task
**And** tasks are ordered by impact: inbox triage (5 min), overdue reviews (5 min), critical health issues (3 min), optional tasks (2 min)
**And** I can skip optional tasks if time is limited

**Given** I perform inbox triage
**When** I run the triage workflow
**Then** items are pre-sorted by age and source type for efficient processing
**And** I can use bulk actions: "archive all web captures older than 14 days"
**And** the interface shows progress: "5 of 12 items processed, ~3 minutes remaining"

**Given** I review overdue items
**When** I check items past their review trigger
**Then** I see only items that directly affect future retrieval (wiki pages, active working notes)
**And** I can bulk-extend review dates for items that are still valid: "extend all by 30 days"
**And** items that rarely get accessed are suggested for archival

**Given** I address critical health issues
**When** I review high-severity findings
**Then** only issues that break core functionality are marked as critical (broken links in wiki, missing required metadata)
**And** I can fix multiple similar issues with batch commands
**And** low-impact issues (orphaned files, minor formatting) are deferred to weekly maintenance

### Story 7.5: Error Handling and Recovery

As Reno,
I want robust error handling that prevents data loss and provides clear recovery paths,
So that I can trust the system even when things go wrong.

**Acceptance Criteria:**

**Given** a PowerShell script encounters an error during execution
**When** the error occurs
**Then** the script logs the full error details to `logs/errors-YYYY-MM-DD.log`
**And** it attempts to complete other operations rather than stopping entirely
**And** it provides a clear error message with suggested next steps
**And** any partial changes are either completed or rolled back to prevent inconsistent state

**Given** I have concurrent access conflicts (multiple scripts running simultaneously)
**When** file locking conflicts occur
**Then** scripts wait up to 30 seconds for locks to be released
**And** if locks persist, the script fails gracefully with a clear message: "Another operation is in progress. Try again in a few minutes."
**And** lock files are automatically cleaned up after 5 minutes to prevent permanent locks

**Given** I encounter corrupted metadata or malformed files
**When** scripts process these files
**Then** corrupted files are quarantined to `quarantine/` folder with error details
**And** the system continues processing other files
**And** I get a summary of quarantined files with suggested repair actions
**And** quarantined files can be manually fixed and restored

**Given** I need to recover from a system failure or data corruption
**When** I run `.\scripts\system-recovery.ps1`
**Then** the script checks Git history for recent changes and offers rollback options
**And** it validates all metadata schemas and reports inconsistencies
**And** it rebuilds indexes and verifies folder structure integrity
**And** it provides a health report showing what was recovered vs. what needs manual attention