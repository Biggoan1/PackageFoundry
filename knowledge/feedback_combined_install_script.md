---
name: Combined install/uninstall script with -Action parameter
description: SCCM packaging scripts should be one .ps1 with a parameter selecting Install or Uninstall, not two separate files
type: feedback
originSessionId: 664a770e-2a03-4392-a261-784fdcc561da
---
For all SCCM application packages, ship a **single PowerShell script** that handles both install and uninstall via a parameter, rather than two separate `_Install.ps1` / `_Uninstall.ps1` files.

Pattern:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Install','Uninstall')]
    [string]$Action
)
# ... shared setup (paths, logging) ...
switch ($Action) {
    'Install'   { <install logic>; exit 0 }
    'Uninstall' { <uninstall logic>; exit 0 }
}
```

SCCM deployment type commands become:
- Install:   `powershell.exe -ExecutionPolicy Bypass -File .\<AppName>.ps1 -Action Install`
- Uninstall: `powershell.exe -ExecutionPolicy Bypass -File .\<AppName>.ps1 -Action Uninstall`

Detection script is NOT a separate .ps1 file - its contents go inline in `SCCM_Commands.txt` between begin/end markers (see feedback_sccm_commands_txt.md).

**Why:** User preference — reduces file sprawl in source folders, keeps shared logic (paths, logging function, version strings) in one place so they can't drift between install and uninstall.

**How to apply:** When creating or updating any SCCM package scripts, use the combined pattern. Retrofit existing packages opportunistically when touching them. Keep the detection script as a separate file.
