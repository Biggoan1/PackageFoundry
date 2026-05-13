---
name: SCCM deployments default to Available, not Required
description: When creating SCCM application deployments, use DeployPurpose Available unless the user explicitly requests Required
type: feedback
originSessionId: 664a770e-2a03-4392-a261-784fdcc561da
---
When creating SCCM application deployments, default to `-DeployPurpose Available` (shows in Software Center, user chooses when to install). Only use `-DeployPurpose Required` (auto-installs) if the user explicitly asks for it.

**Why:** User preference - mandatory/required deployments push installs automatically which isn't always desired, especially during testing. Requested 2026-04-16 after several packages were deployed as Required by default.

**How to apply:** In `New-CMApplicationDeployment`, always use `-DeployPurpose Available` unless told otherwise. Update SCCM_Commands.txt to note the deploy purpose.
