# Agent Handoff

This folder is the local bridge between Codex and Claude Code CLI.

## Files

- `codex-to-claude.md`: prompt Codex writes for Claude.
- `claude-result.json`: raw Claude Code JSON response.
- `claude-result.md`: extracted final Claude response text.

## Run Claude From The Handoff Prompt

```powershell
.\scripts\invoke-claude-handoff.cmd
```

The wrapper uses `claude.cmd` so Windows PowerShell execution policy does not block `claude.ps1`.

By default, Claude gets file/search/edit tools only. If a specific handoff needs shell commands:

```powershell
.\scripts\invoke-claude-handoff.cmd -AllowBash
```
