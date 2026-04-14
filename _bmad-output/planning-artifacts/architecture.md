---
stepsCompleted: [1, 2, 3, 4]
inputDocuments: 
  - "_bmad-output/planning-artifacts/prd.md"
  - "_bmad-output/planning-artifacts/prd-validation-report.md"
  - "_bmad-output/planning-artifacts/prd-validation-report-post-edit.md"
  - "README.md"
  - "bulletproof_2nd_brain_system_v4.md"
  - "llm_wiki_2nd_brain_system_v_3.md"
workflowType: 'architecture'
project_name: 'PinkyAndTheBrain'
user_name: 'Reno'
date: '2026-04-14'
---

# Architecture Decision Document - PinkyAndTheBrain

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
18 FRs spanning knowledge lifecycle management with emphasis on:
- Low-friction capture (FR-001, FR-002, FR-016) 
- Explicit promotion workflows with review gates (FR-003, FR-004, FR-005)
- Comprehensive retrieval and health monitoring (FR-007, FR-008, FR-009)
- Privacy controls and configuration management (FR-012, FR-014)
- Obsidian vault integration and brownfield import (FR-015, FR-018)

**Non-Functional Requirements:**
12 NFRs driving architectural decisions:
- Local-first portability with Markdown compatibility (NFR-001, NFR-002)
- Explicit review gates preventing auto-promotion (NFR-003)
- Inspectable automation with reviewable outputs (NFR-010, NFR-011)
- 15-minute daily maintenance budget constraint (NFR-012)

**Scale & Complexity:**
- Primary domain: Local automation + knowledge management
- Complexity level: Medium (sophisticated workflows, multiple validation layers)
- Estimated architectural components: 8-10 (capture, triage, promotion, retrieval, health, privacy, config, integration)

### Technical Constraints & Dependencies

- **Local-first requirement**: No hosted services, file-based storage
- **Obsidian compatibility**: Vault-safe folders, Markdown files, frontmatter metadata
- **BMad integration**: Must work with existing agent framework and workflow conventions
- **Optional IDE hooks**: VS Code, Cursor, Claude integrations as workflow entry points
- **Authority hierarchy**: Code > Schemas > ADRs > Tasks > Wiki > Working > Raw

### Cross-Cutting Concerns Identified

- **Provenance tracking**: Every knowledge artifact must trace back to sources
- **Metadata management**: Status, confidence, review triggers across all knowledge layers
- **Agent handoff contracts**: Clear interfaces between BMad agents and knowledge workflows  
- **Health monitoring**: Staleness detection, broken links, duplicate concepts, orphaned pages
- **Review gate enforcement**: Preventing noisy AI extractions from becoming trusted knowledge

## Starter Template Evaluation

### Primary Technology Domain

**Knowledge Pipeline Automation** based on multi-source input → processing → Obsidian display architecture

### Starter Options Considered

Based on requirements and team feedback, the **Hybrid File-Based + obsidian-cli** approach is technically sound but needs concrete implementation artifacts.

### Selected Starter: **Hybrid File-Based + obsidian-cli** (Enhanced)

**Rationale for Selection:**
- **Winston**: Sound architectural approach with clean separation of concerns
- **Amelia**: Technically viable but requires concrete implementation skeleton
- **Barry**: Perfect for Quick Flow - lean stack that ships fast, but needs working artifacts

**Enhanced Initialization Approach:**

```bash
# Install obsidian-cli for vault automation
npm install -g obsidian-cli

# Create implementation skeleton (Barry's 30-minute spike)
# Actual folder structure with sample files
# Working PowerShell scripts showing pipeline flow
# Template files with real frontmatter examples
```

**Architectural Decisions Provided by Enhanced Starter:**

**Folder Structure (Concrete Implementation):**
```
knowledge/
  inbox/           # Multi-source inputs
  raw/            # Filtered content  
  working/        # Processing layer
  wiki/           # Final display layer
  schemas/        # Templates with frontmatter
  archive/        # Retired content

scripts/
  triage.ps1      # Inbox processing
  health-check.ps1 # Validation
  obsidian-sync.ps1 # Vault integration

.obsidian/        # Vault configuration
```

**Processing Pipeline (Idempotent Scripts):**
- **Triage automation**: PowerShell scripts for inbox → raw/working/wiki
- **Health monitoring**: Automated staleness detection, broken links, duplicates
- **Provenance tracking**: All operations preserve source metadata (NFR-006)
- **Rollback support**: All file operations reversible (NFR-011)

**Template System (Standardized):**
- **Inbox template**: Minimal capture with source tracking
- **Working note template**: Status, evidence, connections, contradictions
- **Wiki page template**: Summary, sources, metadata, confidence levels
- **All templates**: Frontmatter-driven with obsidian-cli compatibility

**Development Experience:**
- **Manual-first workflow**: Validate process before automation
- **Incremental automation**: Start with templates, add scripts for pain points
- **Error handling**: Concurrent access protection, idempotent operations
- **BMad integration**: Existing agent skills work with file structure

**Implementation Requirements (Team Consensus):**
1. **Concrete artifacts needed** before proceeding to architectural decisions
2. **Working skeleton** with actual templates and scripts
3. **obsidian-cli integration** patterns defined
4. **Error handling** and rollback mechanisms implemented

**Note:** Barry can create the working implementation skeleton in 30 minutes once tech stack is approved. This provides the concrete foundation needed for architectural decision-making.

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
- **Knowledge Processing**: Manual capture with optional automation hooks, explicit review gates (NFR-003)
- **Agent Integration**: File-based contracts with BMad agents, obsidian-cli for vault operations
- **Health Check Strategy**: Karpathy-aligned "lint" operations with automated detection + human review
- **Storage Architecture**: File-based Markdown + frontmatter, Obsidian-compatible vault structure
- **Automation Philosophy**: Manual-first with incremental automation, preserving inspectability (NFR-010)

**Important Decisions (Shape Architecture):**
- **Processing Pipeline**: PowerShell/bash scripts for inbox→raw→working→wiki flow
- **Validation Framework**: Daily quick checks, weekly deep scans, monthly maintenance
- **Provenance Tracking**: All operations preserve source metadata (NFR-006)
- **Error Handling**: Idempotent operations with rollback support (NFR-011)

**Deferred Decisions (Post-MVP):**
- **Advanced automation**: AI-driven content promotion beyond manual review
- **Multi-vault support**: Cross-project knowledge sharing
- **Performance optimization**: Large-scale vault handling
- **Advanced integrations**: Deep IDE hooks beyond basic file operations

### Knowledge Processing Architecture

**Multi-Source Ingestion:**
- **Manual capture**: Templates and folder drops for immediate capture
- **Agent hooks**: BMad agents write structured outputs to staging areas
- **Batch processing**: Scheduled processing of accumulated inputs
- **Review gates**: Human approval required before wiki promotion (NFR-003)

**Processing Pipeline (Karpathy-Aligned):**
- **Ingest**: Sources processed into raw layer with metadata
- **Query**: BMad agents search and synthesize from wiki
- **Lint**: Health checks detect contradictions, staleness, orphans, missing cross-references
- **Maintain**: Automated detection with human-driven repairs

### Agent Integration Architecture

**BMad-PinkyAndTheBrain Bridge:**
- **File-based contracts**: Agents read/write specific file formats in `.ai/handoffs/`
- **obsidian-cli integration**: Standardized vault operations for link updates, file moves
- **Context injection**: Agents receive relevant wiki content via file-based handoff
- **Output capture**: Agent conversations structured into reviewable formats

**Integration Patterns:**
- **Staging workflow**: Agents write to staging, human approves promotion
- **Metadata standards**: Consistent frontmatter across all agent outputs
- **Provenance tracking**: Every wiki update traces back to source agent/session
- **Permission boundaries**: Agents can read wiki, write to staging only

### Health Check & Validation Architecture (Karpathy's "Lint")

**Automated Detection (Research-Based):**
- **Daily quick checks** (5 min): Broken links, orphans, missing metadata
- **Weekly deep scans** (15 min): Staleness (30+ days), duplicates, contradictions
- **Monthly maintenance** (30 min): Archive candidates, cross-reference gaps

**Validation Rules:**
- **Broken links**: Wiki-link scanning for missing targets
- **Staleness**: Date-based aging with "TODO", "planned" markers
- **Contradictions**: Conflicting claims across related pages
- **Orphans**: Notes with no incoming links or references
- **Metadata gaps**: Missing required frontmatter fields

**Health Check Implementation:**
```powershell
# Daily: scripts/health-check-daily.ps1
# Weekly: scripts/health-check-weekly.ps1  
# Output: knowledge/reviews/health-report-YYYY-MM-DD.md
# Pattern: Automated detection → Human review → Selective repair
```

### Infrastructure & Deployment Architecture

**Local-First Operations:**
- **Storage**: Git repository of Markdown files with version history
- **Backup**: Automated git commits + external backup sync
- **Sync**: Git-based synchronization across devices
- **Performance**: Index-based navigation (index.md) + optional search tools

**Maintenance Workflows:**
- **Daily routine**: Health check + inbox triage (15 min total per NFR-012)
- **Weekly routine**: Deep scan + content review
- **Monthly routine**: Archive sweep + optimization
- **Emergency**: Rollback capabilities for all automated operations

### Decision Impact Analysis

**Implementation Sequence:**
1. **Foundation**: Folder structure + templates + basic PowerShell scripts
2. **Agent integration**: BMad handoff contracts + obsidian-cli patterns
3. **Health checks**: Daily/weekly lint operations
4. **Automation**: Incremental processing pipeline enhancement
5. **Optimization**: Performance tuning + advanced tooling

**Cross-Component Dependencies:**
- **Health checks depend on**: Consistent metadata standards across all layers
- **Agent integration depends on**: File-based contract definitions
- **Processing pipeline depends on**: Template standardization and error handling
- **All components depend on**: Obsidian compatibility and local-first architecture
