# Story 0.1: Initial System Setup and Folder Structure

Status: ready-for-dev

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

- [ ] Create PowerShell setup script (AC: Fresh system initialization)
  - [ ] Implement folder structure creation
  - [ ] Add validation and error handling
  - [ ] Create index.md files for each folder
- [ ] Generate default configuration file (AC: Post-setup validation)
  - [ ] Create pinky-config.yaml with all required settings
  - [ ] Add schema definitions in schemas/ folder
  - [ ] Create .gitignore file
- [ ] Implement backup and rollback functionality (AC: Existing directory protection)
  - [ ] Detect existing content
  - [ ] Create timestamped backups
  - [ ] Add confirmation prompts
- [ ] Add comprehensive error handling (AC: Error Scenarios)
  - [ ] Disk space validation
  - [ ] Permission error handling
  - [ ] Cleanup on failure

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

### File List
