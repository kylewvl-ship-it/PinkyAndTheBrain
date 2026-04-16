# Story 0.1: Initial System Setup and Folder Structure

Status: done

## Story

As Reno,
I want to initialize the PinkyAndTheBrain system with the complete folder structure and configuration,
So that I have a working foundation for knowledge management.

## Acceptance Criteria

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

## Tasks / Subtasks

- [x] Create PowerShell setup script (AC: Fresh system initialization)
  - [x] Implement folder structure creation
  - [x] Add validation and error handling
  - [x] Create index.md files for each folder
- [x] Generate default configuration file (AC: Post-setup validation)
  - [x] Create pinky-config.yaml with all required settings
  - [x] Add schema definitions in schemas/ folder
  - [x] Create .gitignore file
- [x] Implement backup and rollback functionality (AC: Existing directory protection)
  - [x] Detect existing content
  - [x] Create timestamped backups
  - [x] Add confirmation prompts
- [x] Add comprehensive error handling (AC: Error Scenarios)
  - [x] Disk space validation
  - [x] Permission error handling
  - [x] Cleanup on failure

### Review Findings

- [x] [Review][Decision] Disk space test — resolved: added failure-path test using non-existent drive (exit 1 assertion)
- [x] [Review][Decision] Permission error test — resolved: added icacls-based write denial test (exit 1 assertion)
- [x] [Review][Patch] Empty backup dir silently succeeds rollback — fixed: added empty-check that throws
- [x] [Review][Patch] Remove-Item before Copy-Item risks broken state — fixed: rename-before-copy pattern with rollback on failure
- [x] [Review][Patch] Dead `$scriptBlock` variable and misleading test names — fixed: removed dead code, renamed tests
- [x] [Review][Patch] Write-Log in catch block could throw — fixed: wrapped with try/catch, used IO.Path.Combine for log paths
- [x] [Review][Defer] Retry-without-recreating logic is pre-existing — script is idempotent via `Ensure-Directory`/`Ensure-File`, not introduced by this diff — deferred, pre-existing
- [x] [Review][Defer] `$Root` fragility when script is moved/symlinked — `$Root = $PSScriptRoot/..` is pre-existing for all operations — deferred, pre-existing

## Dev Notes

### Architecture Requirements

**Local-First Design:**
- All operations must work without hosted services
- File-based storage using Markdown format
- Obsidian-compatible vault structure
- Git repository initialization for version control

**Folder Structure Purpose:**
- `knowledge/inbox/`: Temporary storage for newly captured items awaiting triage
- `knowledge/raw/`: Imported conversations and unprocessed source material
- `knowledge/working/`: Structured documents for developing ideas with templates
- `knowledge/wiki/`: Verified knowledge layer containing trusted information
- `knowledge/schemas/`: Template definitions and metadata schemas
- `knowledge/archive/`: Storage for outdated or replaced knowledge
- `scripts/`: PowerShell automation scripts for all core operations
- `templates/`: Standardized templates with frontmatter schemas
- `.ai/handoffs/`: File-based contracts for BMad agent communication
- `config/`: System configuration files

**PowerShell Script Requirements:**
- Must work on Windows with bash shell
- Idempotent operations (safe to run multiple times)
- Comprehensive error handling and logging
- User-friendly output with progress indicators
- Rollback capabilities for failed operations

**Configuration Management:**
- YAML-based configuration for all system behavior
- Default settings that work out-of-the-box
- Validation of configuration values
- Documentation of all configuration options

### Technical Implementation Details

**Script Architecture:**
- Use PowerShell for Windows compatibility
- Implement proper error handling with try-catch blocks
- Use Write-Host for user feedback with color coding
- Log all operations to `logs/setup.log`
- Return appropriate exit codes (0 for success, non-zero for errors)

**File Operations:**
- Use `New-Item -ItemType Directory` for folder creation
- Check for existing files before overwriting
- Use `Copy-Item` for backup operations
- Implement file locking protection for concurrent access

**Validation Requirements:**
- Check available disk space before starting
- Validate write permissions for target directories
- Verify PowerShell execution policy allows script execution
- Test Git availability for version control setup

### Project Structure Notes

**Obsidian Compatibility:**
- Use vault-safe folder names (no special characters)
- Implement Obsidian-friendly link format `[[page-name]]`
- Preserve frontmatter metadata format
- Ensure all Markdown files are valid

**BMad Integration:**
- Follow existing BMad project conventions
- Use `.ai/handoffs/` for agent communication contracts
- Implement file-based interfaces for agent workflows
- Preserve compatibility with existing BMad skills

**Git Integration:**
- Initialize Git repository in project root
- Create appropriate `.gitignore` for temporary files
- Set up automatic commit hooks for knowledge operations
- Implement rollback capabilities using Git history

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 0: System Foundation]
- [Source: _bmad-output/planning-artifacts/architecture.md#Folder Structure (Concrete Implementation)]
- [Source: _bmad-output/planning-artifacts/prd.md#MVP - Minimum Viable Product]
- [Source: _bmad/bmm/config.yaml - Project configuration patterns]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4

### Debug Log References

### Completion Notes List

- Added a usable PowerShell MVP command surface: setup, capture, triage, search, health-check, and Obsidian index sync.
- Added script-friendly templates, config, `.gitignore`, logs placeholder, and per-folder `index.md` files.
- Aligned the MVP runtime decision on PowerShell and converted knowledge schemas to YAML frontmatter.
- Added `-Rollback`/`-BackupPath` parameters and `Restore-FromBackup` function; rollback hint printed after backup creation.
- Replaced stub Pester tests with real tests covering backup creation, rollback restore, disk space exit code, and permission handling.
- All 6 Pester tests pass (0 failures).

### File List

- `.gitignore`
- `config/pinky-config.yaml`
- `templates/inbox-item.md`
- `templates/working-note.md`
- `templates/wiki-page.md`
- `templates/conversation-import.md`
- `scripts/setup-system.ps1`
- `scripts/capture.ps1`
- `scripts/triage.ps1`
- `scripts/search.ps1`
- `scripts/health-check.ps1`
- `scripts/obsidian-sync.ps1`
- `knowledge/*/index.md`
- `knowledge/schemas/wiki-page-template.md`
- `knowledge/schemas/working-note-template.md`
- `tests/setup-system.Tests.ps1`

## Change Log

- 2026-04-16: Completed tasks 3 & 4 — added rollback option (`-Rollback`/`-BackupPath` params + `Restore-FromBackup` function), replaced stub tests with real Pester tests covering backup/rollback/error handling. All 6 tests pass.
