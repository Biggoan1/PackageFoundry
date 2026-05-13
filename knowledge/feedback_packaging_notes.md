---
name: Ship PACKAGING_NOTES.txt with every package
description: Every SCCM package source folder needs a PACKAGING_NOTES.txt alongside SCCM_Commands.txt
type: feedback
originSessionId: 77fcdc42-7aa5-4d32-9d38-fe4a9336bb21
---
Every SCCM package source folder must include a `PACKAGING_NOTES.txt` at the root, alongside `SCCM_Commands.txt`. Format follows existing examples (e.g. `D:\Sources\Apps\SnippingTool\PACKAGING_NOTES.txt`):

- Title line + `===` underline
- **Source:** upstream URL / vendor / store ID
- **What this is** — one paragraph, what the app does, any prod-relevant quirks
- **How it installs** — install logic, install context (system vs user), any winget/msstore caveats
- **Files in this package** — table of file → purpose
- **Install logs** — paths under `C:\distrib\Logs`
- **Upgrade notes** (when replacing a prior version) — supersedence, what gets retired

**Why:** Future-me / a teammate rebuilding the app in prod needs this to understand non-obvious choices that aren't in `SCCM_Commands.txt` (which is mechanical DT settings only). User flagged that I shipped a Terraform package without notes — caught it after the fact.

**How to apply:** Whenever building or rebuilding an SCCM source folder, write `PACKAGING_NOTES.txt` as part of the same step that produces `SCCM_Commands.txt`. Don't treat it as optional — it's part of the template.
