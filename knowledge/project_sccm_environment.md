---
name: SCCM environment details
description: Site code, server, module path, share layout, and packaging conventions
type: project
---

**Site code:** FU1
**Site server:** sccm1.fafolab.net
**Domain:** FAFOLAB
**Admin account:** FAFOLAB\administrator

**ConfigMgr PowerShell module:**
`C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1`

**Content source share:**
- UNC: `\\sccm1\Sources`
- Local path on sccm1: `D:\Sources`
- Mapped drive available: `S:` (read-only for FAFOLAB\administrator via share ACL)

**Folder structure convention:** `\\sccm1\Sources\<Vendor>\<AppName>\<AppVersion>\`
Example: `\\sccm1\Sources\7-Zip\7-Zip\24.09\7z2409-x64.msi`

**Distribution points:** SCCM1.fafolab.net (single DP, no DP groups)

**Packaging standards:**
- x64 only
- Silent MSI installs: `/qn /norestart`
- Deploy as Available to "All Systems" collection unless told otherwise
- Log to `C:\Windows\Temp\`
- User experience: `-UserNotification DisplaySoftwareCenterOnly` on all deployments (show in Software Center, only notify for computer restarts)

**Why:** Enterprise SCCM packaging environment. All deployments should be production-ready, silent, and idempotent.
**How to apply:** Use these values directly in any SCCM packaging scripts without prompting the user.
