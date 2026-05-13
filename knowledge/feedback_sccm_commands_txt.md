---
name: Ship SCCM_Commands.txt with every package
description: Every SCCM app source folder must include a SCCM_Commands.txt with copy-pasteable DT commands and settings for rebuilding in prod
type: feedback
originSessionId: 664a770e-2a03-4392-a261-784fdcc561da
---
For every SCCM application package, create a `SCCM_Commands.txt` file in the source folder alongside the scripts. It must contain the exact command lines and deployment type settings in copy-paste-ready form, so the user can recreate the application in another SCCM environment (e.g. prod) without having to dig through scripts or memory.

Include at minimum:
- App name and content location
- Install command (exact string)
- Uninstall command (exact string)
- **Detection method script contents inline** (between `----- begin detection script -----` / `----- end detection script -----` markers) - do NOT ship a separate Detect.ps1 file
- Install behavior (system/user), logon requirement, user experience, max run time
- Dependencies (other SCCM apps or prerequisites)
- Product info for MSI-based apps (ProductCode, DisplayVersion, install path)
- Icon filename
- Log file paths the install/uninstall script writes

**Why:** User maintains a separate prod SCCM environment and rebuilds applications there manually. Having the commands in a plain text file in the source folder makes that copy/paste job trivial and eliminates transcription errors. Requested 2026-04-15 after building the Avamar + Zulu JRE 25 packages.

**How to apply:** Create `SCCM_Commands.txt` as part of every new package, and add one to existing packages when you touch them. Keep it plain text - no markdown, no code fences - so it reads cleanly in Notepad.

**HARD RULE - update on every DT change**: any time a deployment type field changes (install command, uninstall command, detection script, install behavior / context, logon requirement, user experience, max run time, dependencies, content location, etc.), update `SCCM_Commands.txt` in the SAME operation that touched the DT. This includes one-off troubleshooting tweaks - if I just ran `Set-CMScriptDeploymentType` or `Set-CMMsiDeploymentType` against an existing app, I have to also push an updated SCCM_Commands.txt to that app's source folder before reporting done. Reinforced 2026-05-06 after I forgot to refresh it after flipping Telerik UI for Blazor VS Extension to InstallForUser. Where useful, leave a short "Why <change> on <date>" note at the bottom so a future reader sees why the file looks the way it does.
