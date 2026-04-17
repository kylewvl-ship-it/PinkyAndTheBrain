# Story 0.5: Git Integration and Version Control

**Story ID:** 0.5  
**Epic:** 0 - System Foundation  
**Status:** ready-for-dev  
**Created:** 2026-04-16  

## User Story

As Reno,  
I want automatic version control for all knowledge files,  
So that I can track changes and recover from mistakes.

## Acceptance Criteria

### Scenario: Initial Git setup
- **Given** the system is initialized with Git integration
- **When** the setup completes
- **Then** a Git repository is initialized in the root directory
- **And** a `.gitignore` file excludes temporary files and system caches
- **And** an initial commit is created with the message "Initial PinkyAndTheBrain setup"
- **And** all template files, scripts, and configuration are committed

### Scenario: Automatic change tracking
- **Given** I perform knowledge management operations
- **When** I create, modify, or move knowledge files
- **Then** changes are automatically staged for commit
- **And** a commit is created with descriptive message: "Knowledge update: [operation] [filename]"
- **And** commits include both the changed file and any updated metadata

### Scenario: Knowledge evolution review
- **Given** I want to review my knowledge evolution
- **When** I run `.\scripts\git-summary.ps1`
- **Then** I see a summary of recent commits grouped by operation type
- **And** I can view the history of any specific knowledge file
- **And** I can see which files have been modified but not yet committed

### Scenario: Mistake recovery
- **Given** I make a mistake and want to recover
- **When** I run `.\scripts\rollback.ps1 -Hours 24`
- **Then** I can see all changes made in the last 24 hours
- **And** I can selectively revert specific files or operations
- **And** the rollback operation itself is committed with a clear message

## Technical Requirements

### Architecture Compliance
- Git repository initialized in system root directory
- Automatic commit hooks for all knowledge operations
- Descriptive commit messages following consistent patterns
- Support for selective rollback and recovery operations

### Git Configuration
- Repository initialization with appropriate `.gitignore`
- Commit message templates for different operation types
- Automatic staging of knowledge files and metadata
- Branch strategy (main branch for production knowledge)

### Commit Message Patterns
```
Initial PinkyAndTheBrain setup
Knowledge capture: [filename] from [source_type]
Knowledge triage: moved [count] items from inbox to [destination]
Knowledge promotion: [filename] from working to wiki
Knowledge archive: [filename] - [archive_reason]
Configuration update: [setting] changed to [value]
System maintenance: [operation_description]
Rollback: reverted [operation] from [timestamp]
```

### Required Scripts
1. **git-summary.ps1** - Repository activity summary and statistics
2. **rollback.ps1** - Selective recovery and rollback operations
3. **git-hooks.ps1** - Automatic commit integration for other scripts

### Integration Points
- All capture operations (from story 0.3) trigger commits
- Triage operations commit batch changes with summary
- Configuration changes (from story 0.4) are automatically committed
- Health check repairs trigger commits with fix descriptions

## Error Scenarios

### Git not installed or accessible
- **Given** Git is not installed or accessible
- **When** the system attempts Git operations
- **Then** it logs a warning about missing version control
- **And** it continues operations without Git integration
- **And** it suggests installing Git for full functionality

### Repository corruption or conflicts
- **Given** the Git repository becomes corrupted
- **When** Git operations fail
- **Then** the system logs detailed error information
- **And** it continues knowledge operations without version control
- **And** it provides instructions for repository recovery

### Disk space issues during commits
- **Given** insufficient disk space for Git operations
- **When** commits are attempted
- **Then** the system displays clear error about disk space
- **And** it suggests cleanup operations or alternative storage
- **And** it preserves knowledge operations even if commits fail

## Previous Story Intelligence
Based on stories 0.1, 0.2, 0.3, and 0.4:
- Complete folder structure exists and needs version control
- All scripts are implemented and need Git integration hooks
- Configuration system is in place and changes need tracking
- Templates and schemas should be version controlled

## Implementation Notes
- Git repository root at system root directory
- Integration hooks in all existing scripts
- Automatic commit messages with operation context
- Support for both automatic and manual commit workflows
- Recovery operations that preserve knowledge integrity

### Git Integration Architecture
```
.git/                          # Git repository
.gitignore                     # Exclude logs, temp files, caches
scripts/
├── git-summary.ps1           # Repository statistics and history
├── rollback.ps1              # Recovery and rollback operations
├── git-hooks.ps1             # Integration hooks for other scripts
└── lib/
    └── git-operations.ps1    # Shared Git utility functions
logs/
├── git-operations.log        # Git operation history
└── rollback-history.log      # Recovery operation log
```

### Automatic Commit Triggers
- File creation in any knowledge folder
- File modification with metadata updates
- Batch operations (triage, promotion, archival)
- Configuration changes
- System maintenance operations

## Definition of Done
- [ ] Git repository initialized with proper `.gitignore`
- [ ] All knowledge operations automatically committed
- [ ] Git summary and rollback scripts implemented
- [ ] Integration hooks added to all existing scripts
- [ ] Error handling for Git failures
- [ ] Recovery operations tested and documented
- [ ] Commit message patterns consistent and descriptive