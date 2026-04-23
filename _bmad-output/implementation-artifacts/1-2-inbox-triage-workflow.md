# Story 1.2: Inbox Triage Workflow

**Story ID:** 1.2  
**Epic:** 1 - Basic Knowledge Lifecycle  
**Status:** done  
**Created:** 2026-04-23

## User Story

As Reno,  
I want to review inbox items using a structured PowerShell interface and assign them to specific knowledge layers,  
So that captured information gets organized appropriately.

## Acceptance Criteria

### Scenario: Basic triage interface
- **Given** I have items in `knowledge/inbox/`
- **When** I run `.\scripts\triage.ps1`
- **Then** I see a numbered list showing: **filename** (not title), capture date, source type, and first 100 characters of content
- **And** I can select items by number (e.g., `1,3,5` or `1-5`) and assign a disposition
- **And** available dispositions are: `[D]elete`, `[A]rchive`, `[R]aw`, `[W]orking`, Wiki-`[C]andidate`
- **And** the interface shows keyboard shortcuts for each action

### Scenario: Delete disposition
- **Given** I select `D` (delete) for inbox items
- **When** the action is processed
- **Then** I am shown a list of the items to be deleted and prompted to confirm before any deletion occurs
- **And** confirmed items are permanently removed from the file system
- **And** I receive a summary: `Deleted 3 items: [filenames]`
- **And** each deletion is logged to `logs/triage-actions.log`

### Scenario: Archive disposition
- **Given** I select `A` (archive) for inbox items
- **When** the action is processed
- **Then** items are moved to `knowledge/archive/`
- **And** frontmatter is updated with: `disposition: "archived"`, `archive_date` (ISO 8601), `archive_reason: "triaged_from_inbox"`
- **And** archived items are excluded from default search results (enforced by `search.ps1` — no change needed in triage)
- **And** I am optionally prompted for a custom archive reason; if provided, it replaces `"triaged_from_inbox"`

### Scenario: Promote to knowledge layers (R, W, C)
- **Given** I select `R`, `W`, or `C` for inbox items
- **When** the action is processed
- **Then** `R` items are moved to `knowledge/raw/` with `disposition: "raw"` updated in frontmatter
- **And** `W` items are moved to `knowledge/working/` with `disposition: "working"` updated in frontmatter
- **And** `C` items remain in inbox with `disposition: "wiki-candidate"` updated in frontmatter
- **And** original capture metadata (`captured_date`, `source_type`, `source_url`, etc.) is preserved for all dispositions
- **And** moved files retain their original filename

### Scenario: Batch processing with filters
- **Given** I want to batch process similar items
- **When** I use `.\scripts\triage.ps1 -SourceType web` or `.\scripts\triage.ps1 -OlderThan 7`
- **Then** only matching items are shown for triage
- **And** I can apply the same disposition to all shown items by entering `all D` (or `all A`, `all R`, etc.)
- **And** filters can be combined: `-SourceType conversation -OlderThan 3`

### Error Scenario: Delete permission failure
- **Given** I confirm deletion of items but lack file system permissions for some
- **When** deletion is attempted
- **Then** the script identifies which specific files could not be deleted with the permission error
- **And** it continues deleting other items that succeed
- **And** it prints guidance such as "Check file permissions or run as administrator"

### Error Scenario: Missing target folder
- **Given** the target folder for a disposition (e.g., `knowledge/raw/`) does not exist at the time of move
- **When** I assign a disposition that requires moving the file
- **Then** the script creates the missing folder
- **And** it logs the folder creation to `logs/triage-actions.log`
- **And** it continues with the move operation

---

## Technical Requirements

### What already exists (built in Epic 0, Story 0.3)

`scripts/triage.ps1` was created in Epic 0 and is the **base** for this story. It already implements:

- `Get-InboxItems`: parses frontmatter, applies `-SourceType`, `-Project`, `-OlderThan` filters, builds 100-char preview
- `Show-InboxItems`: numbered display loop (currently shows `$item.Title` from frontmatter — **needs to show `$item.FileName`**)
- `Get-UserSelection`: reads `"1,3 D"` / `"1-5 D"` format, returns `@{ Action; Items; Disposition }`
- `Process-Disposition`: handles D / A / R / W / C switch, calls `Set-Content`/`Remove-Item`, logs to `logs/triage-actions.log`
- Git auto-commit via `Invoke-GitCommit` in `scripts/lib/git-operations.ps1`
- Startup: loads config, calls `Test-DirectoryStructure`, exits 2 if any required folder missing

Do **NOT** rewrite working behavior. Extend surgically.

### Delta: what needs to change

#### 1. Show filename instead of title in `Show-InboxItems`

Current (line ~115):
```powershell
Write-Host "$($item.Title)" -NoNewline -ForegroundColor Green
```
Required:
```powershell
Write-Host "$($item.FileName)" -NoNewline -ForegroundColor Green
```
The `$item.FileName` property already exists in the `PSCustomObject` built by `Get-InboxItems`.

#### 2. Delete confirmation + summary in `Process-Disposition` switch "D" case

Replace the direct `Remove-Item` block with:
```powershell
"D" {
    # Show confirmation list
    Write-Host "`nItems to be deleted:" -ForegroundColor Yellow
    foreach ($i in $selectedItems) { Write-Host "  - $($i.FileName)" -ForegroundColor Red }
    $confirm = Read-Host "Confirm deletion? (y/N)"
    if ($confirm -notmatch '^[yY]$') {
        Write-Host "Deletion cancelled." -ForegroundColor Gray
        break
    }

    $deletedNames = @()
    $failedNames  = @()
    foreach ($item in $selectedItems) {
        if ($WhatIf) {
            Write-Host "Would delete: $($item.FileName)" -ForegroundColor Yellow
            continue
        }
        try {
            Remove-Item $item.FullPath -Force -ErrorAction Stop
            $deletedNames  += $item.FileName
            $changedFiles  += $item.FullPath
            Write-Log "Deleted item: $($item.FileName)" "INFO" "logs/triage-actions.log"
        }
        catch {
            $failedNames += $item.FileName
            Write-Log "Failed to delete $($item.FileName): $($_.Exception.Message)" "WARN" "logs/triage-actions.log"
            Write-Host "⚠️  Could not delete $($item.FileName): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    if ($deletedNames.Count -gt 0) {
        Write-Host "🗑️  Deleted $($deletedNames.Count) items: $($deletedNames -join ', ')" -ForegroundColor Red
    }
    if ($failedNames.Count -gt 0) {
        Write-Host "Check file permissions or run as administrator for: $($failedNames -join ', ')" -ForegroundColor Yellow
    }
}
```

> **PowerShell 5.1 constraint**: No `??` operator, no ternary `? :`, no null-conditional `?.`. Use `if/else`.

#### 3. Optional custom archive reason in "A" case

After writing the archive file, before logging, prompt for a custom reason:
```powershell
"A" {
    # ... existing move/frontmatter update code ...

    # Optional custom archive reason
    $customReason = ""
    if ([Environment]::UserInteractive) {
        $customReason = Read-Host "Archive reason (press Enter to use default 'triaged_from_inbox')"
    }
    $archiveReasonValue = if ($customReason.Trim() -ne "") { $customReason.Trim() } else { "triaged_from_inbox" }

    # Apply the reason to frontmatter (replaces the hardcoded "triaged_from_inbox" currently baked in)
    $updatedContent = $updatedContent -replace 'archive_reason: triaged_from_inbox', "archive_reason: $archiveReasonValue"
    # ... then Set-Content and Remove-Item as before ...
}
```

Note: The existing code appends `archive_reason: triaged_from_inbox` using string replacement. The custom-reason logic must run BEFORE `Set-Content` writes the file.

#### 4. `all` command in `Get-UserSelection`

Update the prompt string and add an `all` branch before the existing regex:
```powershell
$selection = Read-Host "Select items (e.g., '1,3,5', '1-5', or 'all') and disposition (e.g., '1,3 D' or 'all W')"

if ($selection -match '^q$|^quit$') { return @{ Action = "quit" } }

# all command
if ($selection -match '^all\s+([DARWC])$') {
    return @{
        Action      = "process"
        Items       = 1..$MaxIndex
        Disposition = $matches[1].ToUpper()
    }
}

# existing: "1,3 D" / "1-5 W" pattern
if ($selection -match '^([\d,\-\s]+)\s+([DARWC])$') {
    # ... unchanged ...
}
```

#### 5. Auto-create missing target folder before move (A, R, W cases)

In each disposition case that moves a file, add a folder-existence check before `Set-Content`/`Move-Item`:
```powershell
$targetDir = Split-Path $targetPath -Parent
if (!(Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Write-Log "Created missing folder: $targetDir" "INFO" "logs/triage-actions.log"
}
```
Add this block at the top of the A, R, and W disposition cases, before any file write.

#### 6. Per-item exception handling in A, R, W cases

Wrap the `Set-Content` + `Remove-Item` in each move case with a `try/catch` matching the pattern used for D above, so a single file failure doesn't abort the whole batch.

---

### Architecture compliance (identical to Story 1.1 constraints)

- PowerShell 5.1 compatible — no `??`, no `? :`, no `?.`
- Use `if ($x) { $y } else { $z }` patterns throughout
- Exit codes: 0 = success, 1 = user error, 2 = system error
- All writes via `Set-Content -Encoding UTF8`
- Logging via `Write-Log` in `scripts/lib/common.ps1`
- Git auto-commit pattern from `scripts/lib/git-operations.ps1` must be preserved after successful operations
- `[Environment]::UserInteractive` guard required before any `Read-Host` call

### File structure

```
scripts/
  triage.ps1            # PRIMARY — all changes here
tests/
  triage.Tests.ps1      # NEW — Pester coverage for Story 1.2 deltas
```

No other files need changes.

### Testing requirements

- Tests live in `tests/` using Pester `Describe` / `Context` / `It` blocks — see `tests/capture.Tests.ps1` for the exact pattern
- Use `$TestDrive`, `$env:PINKY_VAULT_ROOT`, `$env:PINKY_FORCE_NONINTERACTIVE = "1"` (the same env-var convention as `capture.Tests.ps1`)
- New test file: `tests/triage.Tests.ps1`
- Required test cases:
  - **Filename display**: `Show-InboxItems` output contains the `.md` filename, not a frontmatter title
  - **Delete confirmation skip**: in non-interactive mode, delete is skipped (or auto-confirmed based on env var handling — pick consistently with capture pattern)
  - **Delete summary**: after successful deletion, output contains `"Deleted N items:"` with correct filenames
  - **Delete permission failure**: wrapping `Remove-Item` in a try/catch means the loop continues; verify remaining items are processed
  - **Archive custom reason**: when `$env:PINKY_ARCHIVE_REASON = "my-reason"` (or equivalent non-interactive path), the archived file's frontmatter contains `archive_reason: my-reason`
  - **`all` command**: `all W` processes all shown items, not just one
  - **Auto-create folder**: if `knowledge/raw/` is missing, processing an R disposition creates the folder and the move succeeds
  - **Filter combined**: `-SourceType web -OlderThan 3` shows only items matching both conditions
- Run focused test suite before and after: `Invoke-Pester tests\triage.Tests.ps1`

### Out of scope for this story

- Working note creation from promoted items (Story 1.3)
- Wiki promotion workflow (Epic 2)
- Search layer archive exclusion — `search.ps1` already excludes `knowledge/archive/` by default (Epic 0); no changes needed here
- `logs/triage-actions.log` rotation or retention policy

---

## Previous Story Intelligence

**From Story 1.1 (Quick Knowledge Capture):**
- PowerShell 5.1 `??` null-coalescing operator is NOT supported — use `if/else`
- `[Environment]::UserInteractive` is the required guard before any `Read-Host`
- `Set-Content -Encoding UTF8` is the only accepted write method
- Exit codes 0/1/2 are established; maintain them
- Pester tests use isolated `$TestDrive` vaults and `$env:PINKY_FORCE_NONINTERACTIVE = "1"` to suppress interactive prompts
- `$PSScriptRoot` reliably resolves `lib/` paths
- 11 pre-existing test failures exist in the full suite; verify they don't increase

**From Story 0.3 (Script Implementation):**
- `triage.ps1` scaffold was created; the base implementation works end-to-end
- The script's outer `try/catch` currently swallows all exceptions and exits 2 — internal per-item error handling must use its own `try/catch` so the outer catch only fires on unrecoverable startup errors
- Template injection uses `.Replace()`, not `-replace`, to avoid regex backreference issues — apply same principle to frontmatter string manipulation where possible

**From git log patterns:**
- Commits in this project follow `"Knowledge triage: [verb] N item(s) from inbox"` format (already wired in triage.ps1)
- No changes to commit message format required

---

## Definition of Done

- [x] `Show-InboxItems` displays `$item.FileName` instead of `$item.Title`
- [x] Delete flow prompts with item list, confirms before removing, and prints summary `"Deleted N items: [filenames]"`
- [x] Delete permission failures are caught per-file; processing continues for other items; guidance printed
- [x] Archive flow prompts for optional custom reason in interactive mode; reason appears in frontmatter
- [x] `all D` / `all A` / `all R` / `all W` / `all C` applies disposition to all currently shown (filtered) items
- [x] Missing target folders (archive/, raw/, working/) are auto-created with folder creation logged
- [x] Filters `-SourceType` and `-OlderThan` work individually and combined
- [x] All existing Epic 0 triage behaviors remain unchanged under focused Story 1.2 regression coverage
- [x] Pester tests in `tests/triage.Tests.ps1` cover all delta behaviors
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] Git auto-commit still fires after successful triage operations
- [x] `[Environment]::UserInteractive` guard wraps all `Read-Host` calls

## Tasks / Subtasks

- [x] Task 1: Update `Show-InboxItems` to display filename
  - [x] Change `$item.Title` to `$item.FileName` in the display line

- [x] Task 2: Add delete confirmation + per-file error handling in "D" case
  - [x] Print item list before deletion and prompt for confirmation
  - [x] Wrap `Remove-Item` in `try/catch` per item
  - [x] Print summary after all deletes: `"Deleted N items: [filenames]"`
  - [x] Print guidance when any delete fails due to permissions

- [x] Task 3: Add optional custom archive reason in "A" case
  - [x] Prompt with `[Environment]::UserInteractive` guard
  - [x] Use custom reason if provided, else default `"triaged_from_inbox"`
  - [x] Ensure prompt runs before `Set-Content` writes the file

- [x] Task 4: Add `all [D|A|R|W|C]` command support in `Get-UserSelection`
  - [x] Update prompt text to mention `all` option
  - [x] Add `all\s+([DARWC])` branch returning `Items = 1..$MaxIndex`

- [x] Task 5: Add auto-create missing target folder before each move (A, R, W cases)
  - [x] Check `Test-Path $targetDir` before each move
  - [x] `New-Item -ItemType Directory -Force` if missing
  - [x] Log folder creation to `logs/triage-actions.log`

- [x] Task 6: Wrap move operations (A, R, W) in per-item `try/catch`
  - [x] Match the error handling pattern used in Task 2 for D

- [x] Task 7: Write Pester tests in `tests/triage.Tests.ps1`
  - [x] Filename display test
  - [x] Delete summary test
  - [x] Permission failure continues test
  - [x] Archive custom reason test
  - [x] `all` command test
  - [x] Auto-create folder test
  - [x] Combined filter test
  - [x] Run `Invoke-Pester tests\triage.Tests.ps1` and confirm pass

## File List

- `scripts/triage.ps1` — all Story 1.2 changes
- `tests/triage.Tests.ps1` — new Pester coverage

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- Focused validation: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\triage.Tests.ps1"`

### Completion Notes List

- Updated the triage display to show the actual markdown filename while keeping the existing preview and metadata layout intact.
- Added one-shot prompt helpers for selection, delete confirmation, and archive reason so interactive prompts remain guarded and focused tests can drive the script without hanging.
- Added delete confirmation, per-file delete error handling, summary output, and permission guidance.
- Added optional custom archive reason support plus auto-create/logging for missing archive/raw/working folders.
- Extended `all` command support and switched `OlderThan` filtering to prefer `captured_date` metadata with file-time fallback.
- Added isolated Pester coverage in `tests/triage.Tests.ps1` for all Story 1.2 delta behaviors.

### Change Log

- 2026-04-23: Story created — ready-for-dev
- 2026-04-23: Implemented triage workflow updates and added focused Pester coverage
- 2026-04-23: Passed Story 1.2 focused validation and marked story done
