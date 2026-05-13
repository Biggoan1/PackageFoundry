---
name: PowerShell from Bash - escaping and script file pattern
description: How to reliably run PowerShell in this environment from the Bash tool
type: feedback
---

Never pass UNC paths or backslash-heavy strings inline via `powershell -Command "..."` from the Bash tool. Bash collapses `\\server\share` to `\server\share` regardless of escaping attempts (`\\\\`, single quotes, heredocs all fail).

**Rule:** Write all non-trivial PowerShell as a `.ps1` file (e.g. `C:\Windows\Temp\script.ps1`) using the Write tool, then execute it with:
```
powershell -ExecutionPolicy Bypass -NonInteractive -File "C:\Windows\Temp\script.ps1"
```

**Why:** Inline `-Command` strings go through bash string interpolation which eats backslashes. The `-File` approach skips bash string handling entirely — the PS1 file is written with correct content by the Write tool.

**How to apply:** Any time a PowerShell command needs UNC paths, backslash-heavy strings, or is more than 2-3 lines, write it to a .ps1 file first.

**Also:** Do NOT use em-dashes (—) or other non-ASCII characters in PS1 files. They cause PowerShell parse errors ("The string is missing the terminator"). Use only ASCII in scripts.
