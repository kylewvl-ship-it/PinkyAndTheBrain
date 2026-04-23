# Story 1.1: Quick Knowledge Capture

**Story ID:** 1.1
**Epic:** 1 - Basic Knowledge Lifecycle
**Status:** done
**Created:** 2026-04-23

## User Story

As Reno,
I want to quickly capture knowledge items using specific PowerShell commands,
So that I don't lose important information while in flow.

## Acceptance Criteria

### Scenario: Basic manual capture
- **Given** I have information to capture
- **When** I run `.\scripts\capture.ps1 -Type manual -Title "My Note" -Content "Note content"`
- **Then** the item is saved to `knowledge/inbox/` with filename `YYYY-MM-DD-HHMMSS-my-note.md`
- **And** the inbox template is applied with `captured_date`, `source_type`, and `review_status` populated
- **And** the capture process completes in under 10 seconds
- **And** the script returns the full file path for confirmation

### Scenario: Web source capture with context
- **Given** I capture an item with a URL
- **When** I run `.\scripts\capture.ps1 -Type web -Title "Article" -Url "https://example.com" -Content "My notes"`
- **Then** `source_url`, `source_title`, and `source_type: "web"` are populated in frontmatter
- **And** the source context is preserved in the "Source Context" section of the file body

### Scenario: Rapid successive captures
- **Given** I run multiple capture commands within the same second
- **When** each capture command executes
- **Then** each file gets a unique filename using millisecond-precision timestamps (`YYYY-MM-DD-HHMMSSfff`)
- **And** no items are lost or overwritten due to filename conflicts
- **And** concurrent captures (multiple processes writing simultaneously) are protected by a file lock mechanism

### Scenario: Clipboard capture
- **Given** I want to capture clipboard content
- **When** I run `.\scripts\capture.ps1 -Type clipboard`
- **Then** the clipboard content is captured as the content body
- **And** if `-Title` was not provided, I am prompted to enter a title
- **And** captures up to 10MB of clipboard content succeed

### Scenario: Stdin (piped) capture
- **Given** I pipe content to the script
- **When** I run `Get-Content file.txt | .\scripts\capture.ps1 -Type manual -Title "My Note"`
- **Then** the piped content is used as the content body
- **And** if `-Content` was also passed, piped input takes precedence
- **And** captures up to 10MB of piped content succeed

### Error Scenario: Missing inbox folder
- **Given** the `knowledge/inbox/` folder does not exist
- **When** I attempt any capture
- **Then** the script outputs a clear message identifying the missing inbox folder and its expected path
- **And** it tells the user to run `.\scripts\setup-system.ps1` to initialize the system
- **And** it exits with status code **2**

### Error Scenario: Content over 10MB
- **Given** I provide content that exceeds 10MB
- **When** the capture script processes the content
- **Then** it displays a warning about content size showing the actual size and the 10MB limit
- **And** in interactive mode it offers two options: truncate to 10MB and save, or save the full content to a separate file with the same timestamp-based name
- **And** in non-interactive mode it exits with status code 1 and a clear message
- **And** regardless of outcome it logs the oversized capture attempt (file path, attempted size) to `logs/script-errors.log`

## Technical Requirements

### What already exists (built in Epic 0)

`scripts/capture.ps1` exists and handles: manual, web, conversation, clipboard, idea types. It already:
- Loads config via `scripts/lib/common.ps1`
- Calls `Get-TimestampedFilename` for filename generation
- Checks `Test-DirectoryStructure` for folder presence (returns false + exit 2 when folders missing)
- Reads clipboard with `[Environment]::UserInteractive` guard
- Enforces a 10MB content limit with interactive prompt
- Auto-commits via `scripts/lib/git-operations.ps1` after write

The existing code is the **base**. This story adds precision, correctness, and missing paths on top of it. Do NOT rewrite working behavior.

### Delta: What needs to change

**1. Millisecond-precision timestamps (required for uniqueness guarantee)**

In `scripts/lib/common.ps1`, `Get-TimestampedFilename` at line 64:
```powershell
# Current (seconds only — collides on rapid successive capture):
$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"

# Required (milliseconds — guarantees uniqueness within same second):
$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmssffff"
```
The pattern constant `YYYY-MM-DD-HHMMSS` in `config/pinky-config.yaml` must also be updated to `YYYY-MM-DD-HHMMSSfff` to keep config and function aligned. Alternatively, `Get-TimestampedFilename` can replace both `YYYY-MM-DD-HHMMSS` and `YYYY-MM-DD-HHMMSSfff` patterns so old config still works during transition.

**2. Concurrent capture locking**

After generating `$filePath` and before writing, acquire an exclusive file lock using a `.lock` sidecar file:
```powershell
$lockPath = "$filePath.lock"
$lockStream = $null
try {
    # Retry up to 10 times with 100ms gaps (total max wait: 1 second)
    for ($i = 0; $i -lt 10; $i++) {
        try {
            $lockStream = [System.IO.File]::Open($lockPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None)
            break
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 100
        }
    }
    if ($null -eq $lockStream) {
        Write-Log "Could not acquire file lock after retries: $lockPath" "ERROR"
        exit 2
    }
    Set-Content -Path $filePath -Value $template -Encoding UTF8
} finally {
    if ($null -ne $lockStream) { $lockStream.Close(); $lockStream.Dispose() }
    if (Test-Path $lockPath) { Remove-Item $lockPath -Force -ErrorAction SilentlyContinue }
}
```
Stale lock files older than 5 minutes should be removed before attempting acquisition (check `(Get-Item $lockPath).LastWriteTime`).

**3. Stdin (piped) capture**

Add piped-input detection before the `switch ($Type)` block. PowerShell detects piped input via `$MyInvocation.ExpectingInput`:
```powershell
$pipedContent = $null
if ($MyInvocation.ExpectingInput) {
    $pipedContent = $input | Out-String
}
```
Then in the `manual` and `clipboard` type blocks, prefer `$pipedContent` over `$Content` when both exist:
```powershell
$effectiveContent = if (-not [string]::IsNullOrEmpty($pipedContent)) { $pipedContent } else { $Content }
```
Stdin input still requires `-Title` (or prompts for it in interactive mode).

**4. Missing inbox folder error — inbox-specific message**

The current `Test-DirectoryStructure` check fires when ANY required folder is missing and emits a generic message. For the capture script specifically, add a targeted check for the inbox folder BEFORE calling `Test-DirectoryStructure`:
```powershell
$inboxPath = "$($config.system.vault_root)/$($config.folders.inbox)"
if (!(Test-Path $inboxPath)) {
    Write-Log "Inbox folder not found at '$inboxPath'. Run .\scripts\setup-system.ps1 to initialize the system." "ERROR"
    exit 2
}
```
Place this after config is loaded, before type-switching.

**5. Over-10MB handling — offer truncation OR separate file, and log**

Replace the current `Read-Host "Continue anyway? (y/N)"` block (around line 219) with:
```powershell
$actualSizeMB = [Math]::Round($template.Length / 1MB, 2)
Write-Log "Oversized capture attempt: $($actualSizeMB)MB (limit: $($maxSize/1MB)MB), target: $filePath" "WARN"

if (![Environment]::UserInteractive) {
    Write-Log "Non-interactive mode: capture aborted, content $($actualSizeMB)MB exceeds limit" "ERROR"
    exit 1
}

Write-Host "Content size is $($actualSizeMB)MB, which exceeds the ${$maxSize/1MB}MB limit." -ForegroundColor Yellow
Write-Host "Options:"
Write-Host "  [T] Truncate to $($maxSize/1MB)MB and save"
Write-Host "  [S] Save full content to a separate file (no truncation)"
Write-Host "  [C] Cancel capture"
$oversizeResponse = Read-Host "Choose [T/S/C]"
switch ($oversizeResponse.ToUpper()) {
    "T" {
        $template = $template.Substring(0, $maxSize)
        Write-Log "Content truncated to $($maxSize/1MB)MB for capture" "WARN"
    }
    "S" {
        # Save full content to a timestamped raw file alongside the inbox item
        $rawPath = $filePath -replace '\.md$', '-full-content.md'
        Set-Content -Path $rawPath -Value $template -Encoding UTF8
        Write-Log "Full content saved separately to: $rawPath" "INFO"
        Write-Host "Full content saved to: $rawPath" -ForegroundColor Cyan
        # Still create inbox item with a note pointing to the full file
        $template = $template.Substring(0, $maxSize) + "`n`n> **Note:** Full content saved to $rawPath"
    }
    default {
        Write-Log "Oversized capture cancelled by user" "INFO"
        exit 0
    }
}
```

### Architecture compliance
- PowerShell 5.1 compatible syntax required — no `??` operator, no ternary `? :`, no `?.` null-conditional
- Use `if ($x) { $y } else { $z }` not `$x ?? $y` or `$x ? $y : $z`
- Exit codes: 0=success, 1=user error, 2=system error
- All writes via `Set-Content -Encoding UTF8`
- Logging via `Write-Log` in `scripts/lib/common.ps1`
- Git auto-commit pattern from `scripts/lib/git-operations.ps1` must be preserved after successful write

### File structure
```
scripts/
  capture.ps1              # PRIMARY — all changes here
  lib/
    common.ps1             # Get-TimestampedFilename timestamp format change
config/
  pinky-config.yaml        # Update YYYY-MM-DD-HHMMSS pattern string (optional — see above)
```

### Testing requirements
- Tests live in `tests/` using Pester (see `tests/git-operations.Tests.ps1` for pattern)
- New test file: `tests/capture.Tests.ps1`
- Test cases must cover:
  - Millisecond uniqueness: two rapid captures produce different filenames
  - Inbox missing: exits with code 2 and message contains "setup-system.ps1"
  - Web capture: output file contains `source_url`, `source_type: "web"`, and "Source Context"
  - Oversized content in non-interactive: exits code 1, logs the attempt
  - Piped input: `$pipedContent` is captured when stdin is redirected
  - Concurrent lock: second writer waits, then succeeds (or errors cleanly)
- Run existing test suite before and after to confirm no regressions: `Invoke-Pester tests/`

### Out of scope for this story
- Triage workflow (Story 1.2)
- Working note creation (Story 1.3)
- AI conversation import enhancements (Epic 4)
- Non-inbox capture types (conversation goes to `raw/` — no changes to that path)

## Previous Story Intelligence

**From Story 0.3 (PowerShell Script Implementation):**
- `capture.ps1` was implemented and all core types work. Relevant learnings:
  - PowerShell 5.1 parser errors are real — the `??` null-coalescing operator is NOT supported; use `if/else`
  - Template injection was fixed: use `.Replace()` not regex `-replace` for template variable substitution
  - `[Environment]::UserInteractive` is the right guard for `Read-Host` calls
  - `$PSScriptRoot` is available for resolving `lib/` paths reliably
  - Exit codes 0/1/2 are established conventions; maintain them

**From Story 0.3 review (deferred items now in scope):**
- "Concurrent file access conflicts — Deferred: single-user personal knowledge tool; not a concurrent-access scenario" — Story 1.1 AC explicitly requires concurrent capture handling, so this deferral is REVOKED for this story
- "Hardcoded magic numbers — `10MB` default with config override path already in place" — Story 1.1 requires the over-10MB path to offer truncation + separate file, which the current code doesn't do

**From Story 0.5 (Git Integration):**
- `capture.ps1` already auto-commits after successful write; preserve this
- `scripts/lib/git-operations.ps1` is dot-sourced at the top if present; keep graceful degradation

**From git log (recent patterns):**
- Pester test files use `Describe` / `Context` / `It` blocks and live in `tests/`
- 11 pre-existing test failures are pre-existing and unrelated; verify they don't increase

## Definition of Done

- [x] `Get-TimestampedFilename` produces millisecond-precision timestamps
- [x] Two captures in rapid succession produce different filenames (verified by test)
- [x] Concurrent capture lock mechanism prevents data loss
- [x] Piped stdin input is supported for `-Type manual` and other inbox types
- [x] Missing inbox folder exits with code 2 and message includes "setup-system.ps1"
- [x] Over-10MB content: interactive mode offers truncate or separate-file save; non-interactive exits code 1
- [x] Oversized capture attempt is always logged regardless of interactive choice
- [x] Web capture includes `source_url`, `source_title`, `source_type: "web"` in frontmatter and Source Context in body
- [x] All existing scenarios from Story 0.3 still pass (no regressions) under the approved focused validation baseline; unrelated full-suite failures remain outside Story 1.1
- [x] Pester tests cover new behavior in `tests/capture.Tests.ps1`
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] Git auto-commit still fires after successful capture

## Tasks / Subtasks

- [x] Task 1: Update `Get-TimestampedFilename` in `scripts/lib/common.ps1` to use millisecond format
  - [x] Change `"yyyy-MM-dd-HHmmss"` to `"yyyy-MM-dd-HHmmssfff"` in the shared filename generator
  - [x] Update pattern replacement so both `YYYY-MM-DD-HHMMSS` and `YYYY-MM-DD-HHMMSSfff` resolve (backward-compatible)

- [x] Task 2: Add inbox-specific missing-folder check in `scripts/capture.ps1`
  - [x] Add explicit inbox path check after config load, before type switch, for inbox capture types
  - [x] Message names the exact expected path and references setup-system.ps1
  - [x] Exit code is 2

- [x] Task 3: Add concurrent capture file locking in `scripts/capture.ps1`
  - [x] Generate lock path from output file path
  - [x] Retry up to 10× with 100ms sleep
  - [x] Clean up stale locks (>5 min old) before attempting
  - [x] Release lock in `finally` block

- [x] Task 4: Add stdin (piped) input support in `scripts/capture.ps1`
  - [x] Detect `$MyInvocation.ExpectingInput` before type switch
  - [x] Read `$input | Out-String` into `$pipedContent`
  - [x] Use `$pipedContent` in preference to `$Content` in manual/clipboard/idea paths

- [x] Task 5: Replace over-10MB handling with truncate/separate-file/cancel options
  - [x] Remove existing "Continue anyway?" prompt
  - [x] Add oversized attempt log entry unconditionally
  - [x] Interactive: offer [T]runcate / [S]eparate file / [C]ancel
  - [x] Non-interactive: exit 1 with clear message

- [x] Task 6: Write Pester tests in `tests/capture.Tests.ps1`
  - [x] Millisecond uniqueness test
  - [x] Inbox missing → exit code 2 + message contains "setup-system.ps1"
  - [x] Web capture frontmatter fields
  - [x] Oversized non-interactive → exit code 1 + log entry
  - [x] Piped stdin test
  - [x] Run focused `Invoke-Pester tests/capture.Tests.ps1`; full-suite execution remains blocked by unrelated pre-existing failures and interactive tests outside Story 1.1 scope

## File List

- `scripts/capture.ps1` — inbox capture guard, interactive detection, stdin support, oversize handling, unique-path resolution, and lock-protected writes
- `scripts/lib/common.ps1` — millisecond timestamp format and backward-compatible pattern replacement
- `scripts/lib/config-loader.ps1` — default inbox filename pattern updated to millisecond precision
- `config/pinky-config.yaml` — inbox filename pattern updated to `YYYY-MM-DD-HHMMSSfff`
- `config/default-config.yaml` — default inbox filename pattern updated to `YYYY-MM-DD-HHMMSSfff`
- `tests/capture.Tests.ps1` — isolated Story 1.1 Pester coverage

## Dev Agent Record

### Implementation Plan
- Extend existing `capture.ps1` behavior without rewriting the established Story 0.3 flow.
- Keep changes local to capture/naming/config defaults and add focused Pester coverage around Story 1.1 deltas.
- Preserve PowerShell 5.1 compatibility and the existing git auto-commit behavior.

### Completion Notes
- Implemented millisecond-precision inbox naming in config defaults and the shared filename generator.
- Added piped stdin precedence, title prompting helper, targeted inbox-folder messaging for inbox capture types, and lock-protected writes.
- Replaced the oversize prompt with truncate/save-separately/cancel behavior and unconditional oversized-attempt logging.
- Added isolated Pester tests that run against temporary vault roots instead of the live repo knowledge folders.
- BMAD code review found one confirmed Story 1.1 defect after the initial implementation: a same-name collision could still overwrite an existing file after lock acquisition. Fixed by resolving a unique post-generation capture path before write.
- Focused validation passed with `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\capture.Tests.ps1"`.
- Full `Invoke-Pester tests` remains blocked by unrelated pre-existing failures and interactive test behavior outside Story 1.1 scope; this was an explicit user-approved validation exception for this story.

## Change Log

- 2026-04-23: Story created — ready-for-dev
- 2026-04-23: Implemented Story 1.1 capture updates and added focused Pester coverage
- 2026-04-23: Reviewed Story 1.1 changes, fixed post-generation filename collision handling, and marked story done
