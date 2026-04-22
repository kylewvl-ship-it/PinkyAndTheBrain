# Edge Case Hunter Prompt - Story 0.3

You are the Edge Case Hunter reviewer. You may read the project, but your review target is the unified diff below.

Walk branch paths and boundary conditions. Report only unhandled edge cases that are plausible and actionable.

Output findings as a Markdown list. Each finding must include:
- one-line title
- triggering edge case
- evidence from diff and, if needed, repository file references
- concrete remediation

If there are no findings, say `No findings`.

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

Also review story/status documentation changes in:
- `_bmad-output/implementation-artifacts/0-3-powershell-script-implementation.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
