---
name: Bash UNC path escaping
description: UNC paths like \\server\share get mangled by bash double-quote escaping — always use .ps1 script files for paths with backslashes
type: feedback
---

When running PowerShell from bash with inline `-Command "..."`, double backslashes in UNC paths get mangled:
- Bash double-quotes: `"\\sccm1\Sources"` → PowerShell receives `\sccm1\Sources` → resolves to `C:\sccm1\Sources` (LOCAL path, not network)
- This causes Test-Path, Get-ChildItem, Add-CMScriptDeploymentType etc. to operate on a local path silently

**Why:** In bash double-quotes, `\\` is interpreted as a single `\`, so `\\server` becomes `\server`.

**How to apply:** For any PowerShell command involving UNC paths (\\server\share), write the logic to a `.ps1` file and run with `-File`. Never use `-Command "..."` with UNC paths. This applies to all SCCM CM module cmdlets that take ContentLocation or other path parameters.
