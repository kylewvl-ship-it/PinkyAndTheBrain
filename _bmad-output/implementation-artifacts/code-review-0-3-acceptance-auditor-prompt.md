# Acceptance Auditor Prompt - Story 0.3

You are an Acceptance Auditor. Review this diff against the spec below. Check for violations of acceptance criteria, deviations from spec intent, missing specified behavior, and contradictions between spec constraints and actual code.

Output findings as a Markdown list. Each finding must include:
- one-line title
- which AC or constraint it violates
- evidence from the diff

If there are no findings, say `No findings`.

## Spec

Story: `0.3 PowerShell Script Implementation`

Acceptance criteria and constraints:
- `capture.ps1 -Type manual -Title "My Note" -Content "Note content"` creates a new file in `knowledge/inbox/` using the inbox template.
- Filename follows `YYYY-MM-DD-HHMMSS-title.md`.
- Metadata fields are populated.
- Script returns the full path of the created file.
- `capture.ps1 -Type conversation -File "conversation.txt" -Service "claude"` imports to `knowledge/raw/` with conversation template.
- Conversation template organizes content into structured sections.
- Metadata includes `conversation_date`, `ai_service`, and `import_date`.
- Original raw conversation file remains available in the raw folder.
- `triage.ps1` lists inbox items with previews, supports number selection, dispositions, moves files, updates metadata, and handles comma-separated selections.
- `search.ps1 -Query "search term" -Layers wiki,working` returns layer indicators, filename, modified date, 2-line preview, relevance scoring of title 100/content 50/metadata 25, max 20 results with option to see more.
- `health-check.ps1 -Type all` scans knowledge files for Missing Metadata, Broken Links, Stale Content, Duplicates, Orphans; each finding shows path, type, severity, suggested repair; targeted checks are supported.
- Required scripts: `capture.ps1`, `triage.ps1`, `search.ps1`, `health-check.ps1`, `obsidian-sync.ps1`.
- Shared functions are in `scripts/lib/`.
- Configuration loads from `config/pinky-config.yaml`.
- Logging goes to `logs/script-errors.log` and `logs/triage-actions.log`.
- Validate input parameters with clear errors.
- Handle file system errors gracefully.
- Provide usage help when invalid parameters are provided.
- Exit codes: 0 success, 1 user error, 2 system error.
- Scripts handle edge cases including missing folders, permissions, corrupted files.
- Support dry-run mode with `-WhatIf`.
- Validate configuration before executing operations.
- Handle concurrent access with file locking where needed.
- PowerShell 5.1 compatibility is required.

## Diff

```diff
diff --git a/scripts/capture.ps1 b/scripts/capture.ps1
index 0f93e94..51c463b 100644
--- a/scripts/capture.ps1
+++ b/scripts/capture.ps1
@@ -3,9 +3,8 @@
 # Captures knowledge items with proper templates and metadata
 
 param(
-    [Parameter(Mandatory=$true)]
     [ValidateSet("manual", "web", "conversation", "clipboard", "idea")]
-    [string]$Type,
+    [string]$Type = "",
     
     [string]$Title = "",
     [string]$Content = "",
@@ -35,6 +34,11 @@ if ($Help) {
     exit 0
 }
 
+if ([string]::IsNullOrEmpty($Type)) {
+    Write-Log "Type parameter is required. Use -Help for usage information." "ERROR"
+    exit 1
+}
+
 try {
     # Load configuration
     $config = Get-Config
@@ -181,9 +185,14 @@ try {
     }
     
     # Check for content size limit (configurable, default 10MB)
-    $maxSize = if ($config.limits.max_content_size) { $config.limits.max_content_size } else { 10MB }
+    $maxSizeRaw = if ($config.limits -and $config.limits.max_content_size) { $config.limits.max_content_size } else { $null }
+    $maxSize = if ($maxSizeRaw) { $maxSizeRaw } else { 10MB }
     if ($template.Length -gt $maxSize) {
         Write-Log "Content exceeds $($maxSize/1MB)MB limit. Consider splitting into multiple files." "WARN"
+        if (![Environment]::UserInteractive) {
+            Write-Log "Non-interactive mode: aborting capture, content too large" "ERROR"
+            exit 1
+        }
         $response = Read-Host "Continue anyway? (y/N)"
         if ($response -ne "y" -and $response -ne "Y") {
             Write-Log "Capture cancelled by user" "INFO"
@@ -193,7 +202,7 @@ try {
     
     # Write file (or show what would be written if WhatIf)
     if ($WhatIf) {
-        Write-Host "Would create file: $filePath" -ForegroundColor Yellow
+        Write-Output "Would create file: $filePath"
         Write-Host "Content preview:" -ForegroundColor Yellow
         Write-Host ($template.Substring(0, [Math]::Min(500, $template.Length))) -ForegroundColor Gray
         if ($template.Length -gt 500) {
diff --git a/scripts/lib/common.ps1 b/scripts/lib/common.ps1
index 6cfa2c5..cf5641c 100644
--- a/scripts/lib/common.ps1
+++ b/scripts/lib/common.ps1
@@ -165,18 +165,16 @@ function Get-Template {
     try {
         $template = Get-Content $templatePath -Raw
         
-        # Replace variables in template with validation
+        # Replace variables using literal string replacement to avoid regex backreference issues
         foreach ($key in $Variables.Keys) {
             $value = $Variables[$key]
-            if ($value -eq $null) { $value = "" }
-            # Escape special regex characters in the key for safe replacement
-            $escapedKey = [regex]::Escape($key)
-            $template = $template -replace "\{\{$escapedKey\}\}", $value
+            if ($null -eq $value) { $value = "" }
+            $template = $template.Replace("{{$key}}", [string]$value)
         }
-        
+
         # Replace timestamp placeholders
         $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
-        $template = $template -replace '\{\{timestamp\}\}', $timestamp
+        $template = $template.Replace('{{timestamp}}', $timestamp)
         
         return $template
     }
```
