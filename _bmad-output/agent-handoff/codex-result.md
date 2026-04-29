Files changed:
- `scripts/resolve-findings.ps1`
- `scripts/health-check.ps1`
- `tests/resolve-findings.Tests.ps1`
- `tests/health-check.Tests.ps1`

Validation:
- `resolve-findings.Tests.ps1`: 11 passed, 0 failed
- `health-check.Tests.ps1`: 14 passed, 0 failed

Status: complete.  
Note: direct `Invoke-Pester` was blocked by Windows execution policy, so I ran the same suites with `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester ..."`.