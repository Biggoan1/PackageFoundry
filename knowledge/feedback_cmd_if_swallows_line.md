---
name: cmd.exe IF consumes the rest of the line as its body
description: `if [not] exist X cmd1 & cmd2` runs cmd2 only when the IF is true. Use parens to split.
type: feedback
originSessionId: dc3ef9fa-cb09-4ee6-84fb-370bdb06f4a2
---
In cmd.exe (`cmd /c "..."` or batch files), the `IF` keyword takes the **entire rest of the line** as its body, including any commands after `&` / `&&` / `||`. So:

```cmd
if not exist C:\distrib\Logs mkdir C:\distrib\Logs & msiexec.exe /i foo.msi /q
```

Parses as: `if NOT EXIST X then run "mkdir X & msiexec /i foo.msi /q"`. When `X` exists, the entire body (including `msiexec`) is **skipped** and cmd exits 0 immediately. The intuition that `&` is a command separator outside the IF is wrong.

**Fix - parenthesize the IF body so only the conditional part is scoped:**

```cmd
(if not exist C:\distrib\Logs mkdir C:\distrib\Logs) & msiexec.exe /i foo.msi /q
```

Or split into two cmd invocations / use `mkdir X 2>nul & msiexec ...` (mkdir of an existing dir errors but `2>nul` swallows it; the `&` always runs msiexec).

**Why:** Burned by this 2026-05-05 packaging CMTrace Open in SCCM. The deployment type's install command was a `cmd /c "if not exist ... mkdir ... & msiexec ..."` shim meant to ensure `C:\distrib\Logs` existed before the msiexec log path. On every machine where the dir already existed, cmd exited 0 in ~50ms without running msiexec. SCCM saw exit 0 -> "success", then detection failed -> deployment reported failed. AppEnforce.log showed the cmd.exe process terminating successfully but with no msiexec child trace.

**How to apply:** Any time a cmd.exe install/uninstall command combines `if exist` / `if not exist` with `&` and a follow-on command, parenthesize the IF or split. For SCCM MSI deployments specifically, just use `Add-CMMsiDeploymentType` (separate memory) so there's no cmd wrapper at all.
