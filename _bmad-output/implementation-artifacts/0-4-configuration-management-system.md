# Story 0.4: Configuration Management System

**Story ID:** 0.4  
**Epic:** 0 - System Foundation  
**Status:** ready-for-dev  
**Created:** 2026-04-16  

## User Story

As Reno,  
I want a comprehensive configuration system that controls all system behavior,  
So that I can customize the system to my specific workflow needs.

## Acceptance Criteria

### Scenario: Default configuration structure
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

### Scenario: Configuration customization
- **Given** I want to customize system behavior
- **When** I edit the configuration file
- **Then** all scripts respect the updated settings immediately
- **And** invalid configurations show clear error messages with suggested fixes
- **And** I can validate the configuration with `.\scripts\validate-config.ps1`

### Scenario: Project-specific settings
- **Given** I have multiple projects with different needs
- **When** I configure project-specific settings
- **Then** I can override global settings per project
- **And** project-scoped operations only affect files tagged with that project
- **And** I can list all projects and their file counts with `.\scripts\list-projects.ps1`

## Technical Requirements

### Architecture Compliance
- Use YAML format for human-readable configuration
- Support hierarchical configuration with section grouping
- Implement configuration validation with schema checking
- Provide default values for all optional settings

### Configuration Schema
The configuration must support these sections:
1. **System paths** - Core directory locations
2. **Folder structure** - Knowledge layer folder names
3. **File naming** - Patterns for different content types
4. **Review cadence** - Automatic review scheduling
5. **Health checks** - Validation thresholds and rules
6. **AI handoff** - Context generation limits
7. **Projects** - Multi-project support settings
8. **Search** - Default search behavior

### Configuration Loading
- Scripts must load configuration at startup
- Support environment variable overrides
- Graceful fallback to defaults for missing values
- Clear error messages for invalid YAML syntax

### Validation Requirements
- Validate all path configurations exist or can be created
- Check numeric values are within reasonable ranges
- Verify pattern strings contain valid placeholders
- Ensure boolean flags are properly typed

## Error Scenarios

### Invalid YAML syntax
- **Given** invalid YAML syntax in configuration file
- **When** any script attempts to read configuration
- **Then** it displays the specific YAML parsing error with line number
- **And** it falls back to default settings with a warning
- **And** it suggests running `.\scripts\validate-config.ps1` for detailed validation

### Missing configuration file
- **Given** the configuration file doesn't exist
- **When** scripts attempt to load configuration
- **Then** they create a default configuration file automatically
- **And** they log the creation of default configuration
- **And** they continue execution with default values

### Invalid path configurations
- **Given** configuration specifies non-existent or inaccessible paths
- **When** scripts attempt to use those paths
- **Then** they display clear error messages about path issues
- **And** they suggest checking permissions and creating missing directories
- **And** they provide the exact paths that failed

## Previous Story Intelligence
Based on stories 0.1, 0.2, and 0.3:
- Folder structure is established and needs to be configurable
- Templates exist and their location should be configurable
- Scripts are implemented and need configuration integration
- Git integration requires configuration for commit patterns

## Implementation Notes
- Configuration file location: `config/pinky-config.yaml`
- Support for configuration validation script
- Integration with all existing scripts from story 0.3
- Default configuration should work out-of-the-box
- Configuration changes should not require system restart

## File Structure Requirements
```
config/
├── pinky-config.yaml          # Main configuration file
├── config-schema.yaml         # Configuration validation schema
└── default-config.yaml        # Backup default configuration
scripts/
├── validate-config.ps1        # Configuration validation utility
├── list-projects.ps1          # Project management utility
└── lib/
    └── config-loader.ps1      # Shared configuration loading functions
```

## Definition of Done
- [ ] Complete configuration schema implemented
- [ ] Configuration validation script working
- [ ] All existing scripts integrated with configuration system
- [ ] Project-specific configuration overrides working
- [ ] Error handling for all configuration scenarios
- [ ] Documentation with configuration examples
- [ ] Default configuration provides working system out-of-the-box