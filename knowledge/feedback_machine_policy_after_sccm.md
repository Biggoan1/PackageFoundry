---
name: Invoke machine policy after SCCM packaging
description: Always trigger machine policy retrieval on local device after finishing any SCCM package create or update
type: feedback
---

After completing any SCCM packaging task (new app, update existing, deployment type change), always run this as the final step:

```powershell
Invoke-WMIMethod -Namespace root\ccm -Class SMS_Client -Name TriggerSchedule -ArgumentList '{00000000-0000-0000-0000-000000000021}'
```

**Why:** User requested this so the local SCCM client picks up policy changes immediately after packaging work.
**How to apply:** Run it via `powershell.exe -ExecutionPolicy Bypass -Command "..."` at the end of every SCCM packaging session before wrapping up.
