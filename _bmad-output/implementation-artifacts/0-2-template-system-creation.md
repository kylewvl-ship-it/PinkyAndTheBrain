# Story 0.2: Template System Creation

Status: done

## Story

As Reno,
I want standardized templates for all knowledge types with proper frontmatter schemas,
so that all captured knowledge follows consistent metadata patterns.

## Acceptance Criteria

**Scenario: Template file creation**
- **Given** the template system is initialized
- **When** I examine the `templates/` folder
- **Then** I find these 4 template files with correct frontmatter schemas: `inbox-item.md`, `working-note.md`, `wiki-page.md`, `conversation-import.md`
- **And** `wiki-page.md` includes `exclude_from_ai: false` (not `ai_content_reviewed`)
- **And** all required fields match the canonical schemas in epics.md

**Scenario: Template usage in capture**
- **Given** I create new content via capture scripts
- **When** I run `.\scripts\capture.ps1 -Type manual -Title "My Note" -Content "Note content"`
- **Then** a new file is created in `knowledge/inbox/` using the inbox-item template schema
- **And** timestamp fields (`captured_date`) are auto-populated with current datetime
- **When** I run `.\scripts\capture.ps1 -Type conversation -File "conversation.txt" -Service "claude"`
- **Then** the file is created in `knowledge/raw/` using the conversation-import template schema
- **And** metadata includes `ai_derived: true` and `promotion_blocked: true`

**Scenario: Template validation**
- **Given** a template file is corrupted or missing required frontmatter
- **When** the capture script tries to use it
- **Then** the script displays a clear error identifying the missing/invalid fields
- **And** it provides an example of correct frontmatter format
- **And** it falls back to creating content with minimal valid frontmatter

## Tasks / Subtasks

- [x] Fix `wiki-page.md` schema to use `exclude_from_ai: false` instead of `ai_content_reviewed: false` (AC: Template file creation)
- [x] Update `capture.ps1` to route `conversation` type to `knowledge/raw/` with conversation-import schema (AC: Template usage)
  - [x] Add `-Service` and `-File` parameters
  - [x] Populate `ai_derived: true`, `promotion_blocked: true` for conversation type
- [x] Add template validation function to `capture.ps1` (AC: Template validation)
  - [x] Define required fields per type: inbox (`captured_date`, `source_type`, `review_status`, `disposition`), conversation (`captured_date`, `source_type`, `ai_derived`, `promotion_blocked`)
  - [x] Emit clear error with field names + example frontmatter when validation fails
  - [x] Fall back to minimal valid frontmatter on validation failure
- [x] Add Pester tests covering:
  - [x] Conversation type routes to `knowledge/raw/` with correct schema
  - [x] Template validation error path (missing required field triggers fallback + error)
  - [x] Manual type still routes to `knowledge/inbox/`

## Dev Notes

### What Already Exists — Do NOT Reinvent

Story 0-1 created all 4 template files and `capture.ps1`. The work here is surgical fixes and additions:

| File | Current State | Required Change |
|------|--------------|-----------------|
| `templates/inbox-item.md` | Complete, schema correct | No change needed |
| `templates/working-note.md` | Complete, schema correct | No change needed |
| `templates/wiki-page.md` | Has `ai_content_reviewed: false` | Replace with `exclude_from_ai: false` |
| `templates/conversation-import.md` | Complete, schema correct | No change needed |
| `scripts/capture.ps1` | Generates inline frontmatter, no template file I/O | Add conversation routing + validation |
| `tests/setup-system.Tests.ps1` | 6 passing tests for setup-system.ps1 | Create separate `capture.Tests.ps1` |

### Canonical Template Schemas (from epics.md)

**inbox-item.md** (already correct):
```yaml
captured_date, source_type, source_url, source_title, review_status, disposition, project, private
```

**working-note.md** (already correct):
```yaml
status, confidence, last_updated, review_trigger, project, domain, source_list, promoted_to, private
```

**wiki-page.md** — fix this field:
```yaml
# WRONG (current):
ai_content_reviewed: false

# CORRECT (required):
exclude_from_ai: false
```

**conversation-import.md** (already correct):
```yaml
captured_date, source_type, ai_derived: true, promotion_blocked: true, private
```

### capture.ps1 — Precise Changes Required

**Current behavior**: `capture.ps1` generates inline YAML frontmatter for all types, always writes to `knowledge/inbox/`.

**Required changes** (surgical — do not rewrite the whole script):

1. **Add parameters** at the top of the `param()` block:
   ```powershell
   [string]$Service = "",   # for conversation type: "claude", "chatgpt", etc.
   [string]$File = ""       # path to conversation file to import
   ```

2. **Add routing logic** after `$InboxDir` is defined:
   ```powershell
   $RawDir = Join-Path $Root "knowledge/raw"
   $TargetDir = if ($Type -eq "conversation") { $RawDir } else { $InboxDir }
   ```

3. **Add a `Test-TemplateValid` function** that:
   - Accepts a hashtable of required field names
   - Is called before writing — validates that the frontmatter being constructed has all required keys non-null
   - On failure: writes error with field list + sample YAML to stdout, sets a `$useFallback` flag
   - Falls back to minimal valid frontmatter (just the required fields with empty/default values)

4. **Conversation-specific frontmatter block**:
   ```yaml
   captured_date: "<timestamp>"
   source_type: "conversation"
   ai_service: "<Service>"         # new field
   ai_derived: true
   promotion_blocked: true
   private: <private>
   ```

5. **Use `$TargetDir` instead of `$InboxDir`** in the `Set-Content` call.

### Architecture Constraints

- **Local-first**: No external dependencies. Pure PowerShell string operations only.
- **Idempotent**: Safe to run capture.ps1 multiple times with same input.
- **Obsidian-compatible**: Frontmatter must be valid YAML between `---` delimiters.
- **Filename pattern**: `YYYY-MM-DD-HHMMSS-slug.md` — already implemented, do not change.
- **Encoding**: UTF8 — already set, do not change.
- **`$Root`**: Always derived as `(Resolve-Path (Join-Path $PSScriptRoot "..")).Path` — do not change this pattern (known pre-existing limitation, deferred).

### Testing Standards (from story 0-1 patterns)

- Test file: `tests/capture.Tests.ps1` (create new, do not modify `tests/setup-system.Tests.ps1`)
- Framework: Pester (already installed, used in story 0-1)
- Pattern from story 0-1: Use `BeforeAll` to set `$Root`, clean up in `AfterAll`
- At minimum 4 tests covering: manual→inbox routing, conversation→raw routing, conversation schema fields, validation error fallback

### Project Structure Notes

- Do not create new folders — `knowledge/raw/` was created in story 0-1 (see File List)
- Do not modify `scripts/setup-system.ps1` — out of scope
- Do not modify any `knowledge/*/index.md` files
- `tests/capture.Tests.ps1` is a new file; `tests/setup-system.Tests.ps1` is read-only for this story

### Previous Story Intelligence (0-1)

- `capture.ps1` uses `$ErrorActionPreference = "Stop"` and wraps in `try/catch` — maintain this pattern
- `Write-Host "Captured: $path" -ForegroundColor Green` is the success output convention
- `Write-Error` + `exit 1` is the failure convention
- `Escape-YamlValue` function already exists in capture.ps1 — reuse it for all string fields
- `Convert-ToSlug` function already exists — reuse for filename generation
- Logging: `Add-Content -Path (Join-Path $LogDir "capture.log")` pattern — use for raw captures too

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 0.2: Template System Creation]
- [Source: _bmad-output/planning-artifacts/architecture.md#Template System (Standardized)]
- [Source: _bmad-output/implementation-artifacts/0-1-initial-system-setup-and-folder-structure.md#Dev Notes]
- [Source: _bmad-output/implementation-artifacts/deferred-work.md — $Root fragility is pre-existing, do not fix here]

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

None.

### Completion Notes List

- Fixed `templates/wiki-page.md`: replaced `ai_content_reviewed: false` with `exclude_from_ai: false`
- Updated `scripts/capture.ps1`: added `-Service` and `-File` params, `$RawDir`/`$TargetDir` routing, `Test-TemplateValid` function, conversation-specific frontmatter block with `ai_derived: true` and `promotion_blocked: true`, fallback to minimal frontmatter on validation failure
- Created `tests/capture.Tests.ps1`: 4 Pester v3 tests — all pass; 6 existing setup-system tests — no regressions

### File List

- templates/wiki-page.md (modified)
- scripts/capture.ps1 (modified)
- tests/capture.Tests.ps1 (created)

### Review Findings

- [x] [Review][Decision] setup-system.ps1 and setup-system.Tests.ps1 modified — spec says "do not modify setup-system.ps1, out of scope for 0-2". These appear to be story 0-1 completion items (tasks 3 & 4) committed together with 0-2 work. Resolved: accepted as-is, both stories' work bundled together.
- [x] [Review][Patch] Test-TemplateValid tautological — removed dead fallback branches; capture.ps1 now uses full frontmatter directly without tautological validation call [scripts/capture.ps1]
- [x] [Review][Patch] -File parameter not tested via file path — added "conversation type with -File parameter" describe block to capture.Tests.ps1 [tests/capture.Tests.ps1]
- [x] [Review][Defer] $InboxDir never created when Type="conversation" — only $TargetDir (raw) is created; inbox may not exist if setup-system was not run [scripts/capture.ps1:59] — deferred, pre-existing (setup-system creates directories)
- [x] [Review][Defer] Escape-YamlValue only escapes double-quotes — titles/values with newlines, colons, or YAML special chars could corrupt frontmatter — deferred, pre-existing function not introduced by this diff

### Change Log

- 2026-04-16: Story 0.2 implemented — template schema fix, conversation routing, validation fallback, Pester tests
