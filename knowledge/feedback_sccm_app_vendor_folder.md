---
name: SCCM apps always go in a vendor folder (with fuzzy publisher match)
description: New SCCM apps land in FU1:\Application\<Publisher>. Resolve folder BEFORE creating the app; fuzzy-match the publisher against existing folders so e.g. "Microsoft, Inc" lands in the existing "Microsoft" folder.
type: feedback
originSessionId: dc3ef9fa-cb09-4ee6-84fb-370bdb06f4a2
---
When creating a new SCCM application in the FU1 site, every packaging flow must end with the app in a vendor folder under `FU1:\Application\`. New apps must NOT be left at the Application root.

`New-CMApplication` has no `-FolderPath` parameter, so the placement happens via `Move-CMObject` after creation. But **resolve the destination folder before you start the create flow** so you never end up in a state where the app exists at the root with nothing pointing it at a folder.

**Folder-resolution rules (in order):**

1. **Normalize the publisher**: strip case, trailing whitespace, and common corporate suffixes:
   - `, Inc.` / ` Inc.` / `, Incorporated`
   - `, Corporation` / ` Corporation` / `, Corp.` / ` Corp.`
   - `, LLC` / ` LLC` / `, L.L.C.`
   - `, Ltd.` / ` Ltd.` / `, Limited`
   - `, GmbH` / `, S.A.` / `, S.r.l.` / `, Pty Ltd` / `, Co., Ltd`
2. **Compare against existing folders** (also normalized, case-insensitive). If a match exists, use the **existing folder's exact name** as it appears in the console - do not rename existing folders to fit a new app.
3. **No match -> create a new folder** named after the normalized publisher.

So `Microsoft, Inc` -> existing `Microsoft\` folder. `NVIDIA Corporation` -> existing `NVIDIA\` folder. `Acme Widgets, LLC` with no existing match -> new `Acme Widgets\` folder.

**Helper to use in every Stage-And-CreateApp.ps1:**

```powershell
function Resolve-VendorFolder {
    param([Parameter(Mandatory)][string]$Publisher)

    $normalize = {
        param([string]$s)
        # Strip trailing corporate suffixes; case-insensitive; tolerate optional comma + whitespace before suffix
        ($s -replace '(?i)[,\s]+(Inc|Incorporated|Corporation|Corp|LLC|L\.L\.C\.|Ltd|Limited|GmbH|S\.A\.|S\.r\.l\.|Pty\s*Ltd|Co\.?\s*Ltd)\.?\s*$','').Trim()
    }

    $needle = & $normalize $Publisher
    if (-not $needle) { throw "Empty publisher; cannot resolve folder." }

    $existing = Get-ChildItem 'FU1:\Application' -ErrorAction SilentlyContinue |
        Where-Object { $_.SmsProviderObjectPath -match 'ObjectContainerNode' -or $_.PSIsContainer }

    foreach ($f in $existing) {
        if ((& $normalize $f.Name) -ieq $needle) {
            return $f.Name   # reuse existing folder, even if name differs from $Publisher
        }
    }

    # No match - create new folder using the normalized form
    $new = "FU1:\Application\$needle"
    if (-not (Test-Path $new)) { New-Item -Path $new -ItemType Directory | Out-Null }
    return $needle
}

# Usage at the END of the create flow, after New-CMApplication / Add-CM*DeploymentType /
# Start-CMContentDistribution / New-CMApplicationDeployment / machine-policy trigger:
$folderName = Resolve-VendorFolder -Publisher $Publisher
Move-CMObject -InputObject (Get-CMApplication -Name $AppName) `
              -FolderPath "FU1:\Application\$folderName"
```

**Existing folders as of 2026-05-05** (reuse before creating new): 7-Zip, ABB, Adam Gell, Adobe, Anthropic, Azul Systems, Dell EMC, FAFOLAB, Git, Greenshot, HashiCorp, Microsoft, MscrmTools, Notepad++, NVIDIA, OBS Project, Progress Telerik.

**Why:** User asked for SCCM hygiene 2026-05-05 - rather than dozens of apps at the Application root, organize by publisher. Then refined: fuzzy-match the publisher so vendor variants ("Microsoft, INC", "NVIDIA Corporation") consolidate into the canonical existing folder rather than spawning near-duplicate sibling folders.

**How to apply:**

- Add `Resolve-VendorFolder` + the Move-CMObject call at the end of every `Stage-And-CreateApp.ps1` / `Create-SCCMApp.ps1` flow.
- Skip in **Standalone mode** (Mode=Standalone in CCM_Env.md) - that mode doesn't touch the SCCM site at all.
- Verification: `Get-CMApplication`'s exposed properties do NOT show folder placement. To confirm a move took, query `SMS_ObjectContainerItem` WMI on the site server (`root\sms\site_FU1`) and join with `SMS_ObjectContainerNode`. Do not trust `Get-CMApplication | Select ObjectPath` - that comes back blank even when the app is correctly foldered.
