---
name: PackageFoundry is the brand name for this agent
description: The SCCM packaging agent is branded PackageFoundry; use that name consistently in code, docs, file names, and prose going forward.
type: project
originSessionId: dc3ef9fa-cb09-4ee6-84fb-370bdb06f4a2
---
The Claude Code packaging agent for FAFOLAB SCCM work is named **PackageFoundry**. Renamed from "SCCM-Agent" on 2026-05-11. Use the new name everywhere going forward - inside code, file names, archive names, generated docstrings, prompts, README text.

**Why:** User picked the brand name on 2026-05-11. Anything still saying "SCCM-Agent" or "SCCM Agent" is stale - should be updated when touched.

**How to apply:**

Canonical names / paths:
- Deliverable folder on source box: `C:\distrib\PackageFoundry\`
- Recipient default extract path:   `C:\PackageFoundry\`
- Archive output:                   `C:\distrib\PackageFoundry.7z`
- Single-file bootstrap:            `C:\distrib\Bootstrap-PackageFoundry.ps1`
- Inside-folder installer:          `Install-PackageFoundry.ps1`
- Top-level refresh script:         `C:\distrib\Refresh-PackageFoundry.ps1`
- Top-level build script:           `C:\distrib\Build-Bootstrap.ps1`
- CLAUDE.md heading:                `# PackageFoundry`

What did NOT change:
- The internal slash commands (`/sccm-deploy`, `/sccm-find-icon`, `/vs-layout`) are functionally named and stay as-is.
- `Install-CCMClient.ps1` (helper for ccmsetup on target machines) is not the PackageFoundry installer; name stays.
- `CCM_Env.md` field names and content - unchanged.
- Knowledge file names and content - unchanged.

When generating new documentation, packaging notes, or any user-facing string, use **PackageFoundry** as the product name. Avoid "the agent" as a noun for the product when "PackageFoundry" works.
