---
name: SCCM package logs go to C:\distrib\Logs
description: All SCCM install/uninstall scripts must write logs under C:\distrib\Logs, not C:\Windows\Temp
type: feedback
originSessionId: 664a770e-2a03-4392-a261-784fdcc561da
---
Every SCCM package install/uninstall script must write its logs to `C:\distrib\Logs\<AppName>.log`. This includes any secondary logs the script generates (e.g. msiexec `/l*v` logs, robocopy logs, etc.).

Pattern:

```powershell
$logDir = 'C:\distrib\Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$log = Join-Path $logDir '<AppName>.log'
```

For msiexec logs:
```powershell
'/l*v', (Join-Path $logDir 'OpenSC_Install.log')
```

Update the `Logs:` section of `SCCM_Commands.txt` to reference the `C:\distrib\Logs\` paths.

**Why:** User preference — centralized log location across the fleet makes troubleshooting and log collection straightforward. Requested 2026-04-15.

**How to apply:** Use `C:\distrib\Logs` as the log directory in every new SCCM packaging script. Retrofit existing packages when touching them. Always `New-Item -Force` the directory first since it may not exist on a fresh machine.
