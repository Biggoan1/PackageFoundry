---
name: sccm1 remote PowerShell limitations
description: Get-Content -Raw fails in PSSession on sccm1; C:\Temp may not exist; use workarounds
type: feedback
---

Do not use `Get-Content -Raw` when reading files inside a remote `Invoke-Command` / PSSession on sccm1 — the PS version there does not support the `-Raw` parameter.

Use `(Get-Content "path") -join "\`r\`n"` instead.

Also, `C:\Temp` does not exist on sccm1 by default. Before using `Copy-Item -ToSession` with a `C:\Temp\...` destination, create it first via `Invoke-Command`:
```powershell
Invoke-Command -Session $Session -ScriptBlock {
    if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null }
}
```

**Why:** Hit both issues packaging NVIDIA Control Panel — the `-Raw` param caused `$DetectScript` to be null, which cascaded into a failed deployment type and broken content distribution.

**How to apply:** Any time a Create-SCCMApp.ps1 script reads a file inside a remote session, use the join pattern and pre-create C:\Temp.
