---
name: Elevated PowerShell does not inherit mapped drives
description: Start-Process -Verb RunAs loses mapped drives like S:
type: feedback
---

When running a script elevated via `Start-Process powershell.exe -Verb RunAs -Wait`, the elevated process does NOT inherit mapped drives from the parent session. A drive like S: mapped to \\sccm1\Sources in the user session is invisible to the elevated process.

**Why:** Windows UAC elevation creates a new token/session context; drive mappings are per-session and not shared across elevation boundaries.

**How to apply:** Always use UNC paths (\\server\share) in scripts that will be run elevated, not drive letters. Never rely on mapped drives in elevated contexts.
