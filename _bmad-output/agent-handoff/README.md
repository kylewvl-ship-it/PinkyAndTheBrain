# Agent Handoff

This folder is the local bridge between Codex CLI and Claude Code CLI.

## Files

- `codex-to-claude.md`: prompt Codex writes for Claude.
- `claude-result.json`: raw Claude Code JSON response.
- `claude-result.md`: extracted final Claude response text.
- `claude-to-codex.md`: prompt Claude writes for Codex.
- `codex-result.md`: final Codex response text.
- `codex-result.log`: raw Codex CLI output.

## Run Claude From The Handoff Prompt

```powershell
.\scripts\invoke-claude-handoff.cmd
```

The wrapper uses `claude.cmd` so Windows PowerShell execution policy does not block `claude.ps1`.

By default, Claude gets file/search/edit tools only. If a specific handoff needs shell commands:

```powershell
.\scripts\invoke-claude-handoff.cmd -AllowBash
```

## Run Codex From The Handoff Prompt

```powershell
.\scripts\invoke-codex-handoff.cmd
```

This runs `codex.cmd exec --full-auto` against `claude-to-codex.md` and writes the last Codex message to `codex-result.md`.

If Claude is explicitly asking for a review-only pass:

```powershell
.\scripts\invoke-codex-handoff.cmd -Review
```

That runs `codex.cmd review --uncommitted` and writes the review output to `codex-result.md`.

## Suggested Orchestration Pattern

1. Claude writes the next Codex task to `claude-to-codex.md`.
2. Run the Codex wrapper.
3. Claude reads `codex-result.md` and decides the next step.
4. When Claude needs to act, it writes `codex-to-claude.md`.
5. Run the Claude wrapper.
6. Repeat until the current story is done.
