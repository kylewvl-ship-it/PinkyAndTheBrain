# Configuration

PinkyAndTheBrain loads configuration from `config/pinky-config.yaml` every time a script starts. If the file is missing, scripts recreate it from `config/default-config.yaml` and continue with defaults.

Validate changes with:

```powershell
.\scripts\validate-config.ps1
```

Create or reset a missing config with:

```powershell
.\scripts\validate-config.ps1 -Fix
```

## Environment Overrides

Use environment variables for temporary overrides without editing YAML:

```powershell
$env:PINKY_VAULT_ROOT = ".\knowledge"
$env:PINKY_TEMPLATE_ROOT = ".\templates"
$env:PINKY_SEARCH_MAX_RESULTS = "50"
$env:PINKY_SEARCH_INCLUDE_ARCHIVED = "true"
$env:PINKY_SEARCH_CASE_SENSITIVE = "false"
```

## Project Overrides

Project-scoped config can override global settings by project name:

```yaml
projects:
  default_project: "general"
  create_subfolders: true
  overrides:
    PinkyAndTheBrain:
      search:
        max_results: 50
        include_archived: true
```

Use project scope in supported scripts:

```powershell
.\scripts\capture.ps1 -Type manual -Title "Decision" -Content "..." -Project PinkyAndTheBrain
.\scripts\search.ps1 -Query "decision" -Project PinkyAndTheBrain
.\scripts\triage.ps1 -Project PinkyAndTheBrain
.\scripts\list-projects.ps1
```
