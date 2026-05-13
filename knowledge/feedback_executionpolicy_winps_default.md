---
name: Win PS 5.1 default ExecutionPolicy is Restricted
description: On Windows client SKUs, Win PS 5.1's effective ExecutionPolicy when all scopes are Undefined is Restricted; profiles silently skip. Fix via GPO.
type: feedback
originSessionId: dc3ef9fa-cb09-4ee6-84fb-370bdb06f4a2
---
On Windows client SKUs (Pro/Home), **Windows PowerShell 5.1's effective ExecutionPolicy when every scope is Undefined is `Restricted`** — which silently blocks profile scripts (`Microsoft.PowerShell_profile.ps1`) and any unsigned `.ps1`. PowerShell 7 defaults to `RemoteSigned` and is unaffected.

The 5.1 console doesn't surface this at startup unless you watch closely; the user just sees "no profile" and assumes the file is missing or in the wrong location.

**Why:** Confirmed 2026-05-01 after deploying the FAFOLAB system-wide PS profile via SCCM. Files landed correctly at `$PSHOME\Microsoft.PowerShell_profile.ps1` for both editions and the FAFOLAB registry detection marker was set, but 5.1 silently skipped the profile because LocalMachine policy was Undefined. PS7 loaded it fine. User fixed by setting a GPO rather than per-machine `Set-ExecutionPolicy`.

**How to apply:** When packaging or deploying any unsigned PowerShell content meant to run under Win PS 5.1 (system-wide profiles, login scripts, helper modules), assume Restricted is in force and configure ExecutionPolicy via GPO:

  Computer Configuration -> Administrative Templates -> Windows Components ->
    Windows PowerShell -> "Turn on Script Execution"
  Set: Enabled, "Allow local scripts and remote signed scripts"

GPO wins over `Set-ExecutionPolicy -Scope LocalMachine`. Don't suggest copying profiles to per-user directories as a workaround - same policy blocks them. For long-term clean, code-sign and use AllSigned.

Sanity check from PowerShell:
```
Get-ExecutionPolicy -List      # all Undefined => effective Restricted on client SKUs
```
