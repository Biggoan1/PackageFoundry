Manage Visual Studio 2026 layout repositories and SCCM deployments for VS Pro and Enterprise. Arguments: `$ARGUMENTS` (action: create|update|add-workload|remove-workload|deploy, edition: pro|enterprise, and any workload/path details).

---

## Key Concepts

**Bootstrapper** — Small (~1 MB) .exe that downloads and drives installation. Always run elevated. Use `--wait` in scripts so exit codes are accurate.

**Layout** — A network/local cache of all VS packages. Acts as both the install source AND update source for clients. Stored on a file share, clients never need internet access.

**response.json** — File in layout root that sets default install options for clients (workloads, update channel, removeOos, etc.).

**layout.json** — Tracks what workloads/components are in the layout. Reused automatically on `--layout` updates — no need to re-specify workloads.

**vsconfig file** — Exportable list of workloads/components. Can be used to define layout contents or client installs.

---

## Bootstrapper URLs (VS 2026)

| Edition | URL |
|---|---|
| Enterprise | `https://aka.ms/vs/stable/vs_enterprise.exe` |
| Professional | `https://aka.ms/vs/stable/vs_professional.exe` |
| Community | `https://aka.ms/vs/stable/vs_community.exe` |
| Build Tools | `https://aka.ms/vs/stable/vs_buildtools.exe` |

For a **fixed version** (pinned to a specific release): download from the VS 2026 Release History page instead of the evergreen URL above.

---

## Layout Storage (FAFOLAB)

```
D:\Sources\VisualStudio\
  Layouts\
    VS2026-Enterprise\     ← layout root for Enterprise
    VS2026-Professional\   ← layout root for Professional
  Bootstrappers\
    vs_enterprise.exe      ← keep a copy here for layout operations
    vs_professional.exe
```

Layouts must be on a path shorter than 80 characters.
Estimated disk space: ~50 GB per edition (full layout).

---

## Phase 1 — Create a New Layout

Run from an elevated prompt on a machine with internet access. The bootstrapper saves `layout.json` so workloads only need to be specified once.

**Enterprise (common workloads + English only):**
```cmd
vs_enterprise.exe --layout "D:\Sources\VisualStudio\Layouts\VS2026-Enterprise" ^
  --add Microsoft.VisualStudio.Workload.ManagedDesktop ^
  --add Microsoft.VisualStudio.Workload.NetWeb ^
  --add Microsoft.VisualStudio.Workload.Azure ^
  --add Microsoft.VisualStudio.Workload.NativeDesktop ^
  --add Microsoft.VisualStudio.Workload.Data ^
  --includeRecommended ^
  --lang en-US ^
  --passive --wait
```

**Professional (same workloads):**
```cmd
vs_professional.exe --layout "D:\Sources\VisualStudio\Layouts\VS2026-Professional" ^
  --add Microsoft.VisualStudio.Workload.ManagedDesktop ^
  --add Microsoft.VisualStudio.Workload.NetWeb ^
  --add Microsoft.VisualStudio.Workload.Azure ^
  --add Microsoft.VisualStudio.Workload.NativeDesktop ^
  --add Microsoft.VisualStudio.Workload.Data ^
  --includeRecommended ^
  --lang en-US ^
  --passive --wait
```

After creation, set `response.json` so clients get updates from the layout (not the internet):
```json
{
  "channelUri": "\\\\sccm1\\Sources\\VisualStudio\\Layouts\\VS2026-Enterprise\\ChannelManifest.json",
  "removeOos": true,
  "useLatestInstaller": true
}
```

---

## Phase 2 — Update an Existing Layout

Re-run the bootstrapper with just `--layout` — it reads `layout.json` and updates all existing components to the latest version. No need to re-specify workloads.

```cmd
vs_enterprise.exe --layout "D:\Sources\VisualStudio\Layouts\VS2026-Enterprise" --passive --wait
```

**Best practice:** Update layouts on Patch Tuesday (2nd Tuesday of month). Always update to a staging location first, then xcopy to the live share:
```cmd
vs_enterprise.exe --layout "C:\VSLayoutStaging" --passive --wait
xcopy /e /y C:\VSLayoutStaging \\sccm1\Sources\VisualStudio\Layouts\VS2026-Enterprise\
```

**Verify layout integrity after update:**
```cmd
vs_enterprise.exe --layout "D:\Sources\VisualStudio\Layouts\VS2026-Enterprise" --verify
```

**Fix corrupt/missing files:**
```cmd
vs_enterprise.exe --layout "D:\Sources\VisualStudio\Layouts\VS2026-Enterprise" --fix
```

**Remove old cached packages** (saves disk space after updates):
```cmd
vs_enterprise.exe --layout "D:\Sources\VisualStudio\Layouts\VS2026-Enterprise" ^
  --clean "D:\Sources\VisualStudio\Layouts\VS2026-Enterprise\Archive\<GUID>\Catalog.json"
```

---

## Phase 3 — Add Workloads to an Existing Layout

Adding a workload also updates all existing layout content to the latest version:
```cmd
vs_enterprise.exe --layout "D:\Sources\VisualStudio\Layouts\VS2026-Enterprise" ^
  --add Microsoft.VisualStudio.Workload.Python ^
  --includeRecommended ^
  --passive --wait
```

To also update the client's default workload selection, edit the `add` section in `response.json` to include the new workload ID.

---

## Common Workload IDs

| ID | Description |
|---|---|
| `Microsoft.VisualStudio.Workload.CoreEditor` | VS core editor (always included) |
| `Microsoft.VisualStudio.Workload.ManagedDesktop` | .NET desktop development |
| `Microsoft.VisualStudio.Workload.NetWeb` | ASP.NET and web development |
| `Microsoft.VisualStudio.Workload.Azure` | Azure development |
| `Microsoft.VisualStudio.Workload.Data` | Data storage and processing |
| `Microsoft.VisualStudio.Workload.NativeDesktop` | Desktop development with C++ |
| `Microsoft.VisualStudio.Workload.Python` | Python development |
| `Microsoft.VisualStudio.Workload.Node` | Node.js development |
| `Microsoft.VisualStudio.Workload.Office` | Office/SharePoint development |
| `Microsoft.VisualStudio.Workload.DataScience` | Data science |
| `Microsoft.VisualStudio.Workload.ManagedGame` | Game development with Unity |
| `Microsoft.VisualStudio.Workload.NativeGame` | Game development with C++ |
| `Microsoft.VisualStudio.Workload.Universal` | WinUI application development |
| `Microsoft.VisualStudio.Workload.VisualStudioExtension` | VS extension development |

Append `;includeRecommended` or `;includeOptional` per-workload:
```
--add Microsoft.VisualStudio.Workload.Azure;includeRecommended
```

---

## Phase 4 — SCCM Package (Script Deployment Type)

VS bootstrapper installs require SYSTEM elevation — `InstallForSystem` / `WhetherOrNotUserLoggedOn`.

**Content location:** `\\sccm1\Sources\VisualStudio\Layouts\VS2026-Enterprise\` (the layout IS the content — no separate staging needed)

**Install script** (`Scripts\Install-VSEnterprise.ps1`):
```powershell
$bootstrapper = '\\sccm1\Sources\VisualStudio\Layouts\VS2026-Enterprise\vs_enterprise.exe'
$proc = Start-Process -FilePath $bootstrapper -ArgumentList `
    '--quiet --wait --norestart --noWeb ' +
    '--add Microsoft.VisualStudio.Workload.ManagedDesktop ' +
    '--add Microsoft.VisualStudio.Workload.NetWeb ' +
    '--add Microsoft.VisualStudio.Workload.Azure ' +
    '--includeRecommended' `
    -Wait -PassThru
exit $proc.ExitCode
```

**Uninstall script** (`Scripts\Uninstall-VSEnterprise.ps1`):
```powershell
$installer = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'
if (-not (Test-Path $installer)) { exit 0 }
$proc = Start-Process -FilePath $installer -ArgumentList `
    'uninstall --productId Microsoft.VisualStudio.Product.Enterprise --channelId VisualStudio.18.Release --quiet --wait' `
    -Wait -PassThru
exit $proc.ExitCode
```

**Detection script** (`Scripts\Detect-VSEnterprise.ps1`):
```powershell
$minVersion = [version]'18.0'
$installs = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                           'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' `
    -ErrorAction SilentlyContinue |
    Get-ItemProperty |
    Where-Object { $_.DisplayName -like 'Microsoft Visual Studio*Enterprise*' -and $_.DisplayVersion }

foreach ($i in $installs) {
    try {
        if ([version]($i.DisplayVersion -replace '[^0-9.]') -ge $minVersion) {
            Write-Output 'Installed'
            break
        }
    } catch {}
}
```

**SCCM deployment type settings:**
- `InstallationBehaviorType`: `InstallForSystem`
- `LogonRequirementType`: `WhetherOrNotUserLoggedOn`
- `MaximumRuntimeMins`: `120` (VS installs take time)
- `EstimatedRuntimeMins`: `60`

**Important:** Do NOT use `--noWeb` in the install command if clients have internet — it prevents component download if a workload isn't fully in the layout. Only use `--noWeb` for fully offline environments where the layout contains everything.

---

## Phase 5 — Modify an Existing VS Installation (Add/Remove Workloads)

To add workloads to an already-installed VS instance via SCCM, use `setup.exe modify`:
```powershell
$installer = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'
$proc = Start-Process -FilePath $installer -ArgumentList `
    'modify --installPath "C:\Program Files\Microsoft Visual Studio\18\Enterprise" ' +
    '--add Microsoft.VisualStudio.Workload.Python --includeRecommended ' +
    '--quiet --wait --norestart' `
    -Wait -PassThru
exit $proc.ExitCode
```

---

## Exit Codes (bootstrapper + installer)

| Code | Meaning |
|---|---|
| 0 | Success |
| 3010 | Success, reboot required |
| 1641 | Success, reboot initiated |
| 1602 | User cancelled |
| 1618 | Another installer running |
| 5003 | Bootstrapper failed to download |
| 740 | Elevation required |
| 8006 | VS processes running (close VS first) |

Treat 0, 3010, and 1641 as success in SCCM exit code configuration.

---

## Key Flags Reference

| Flag | Use |
|---|---|
| `--quiet` | No UI at all |
| `--passive` | Progress UI, no interaction |
| `--wait` | Block until complete (required for accurate exit codes in scripts) |
| `--norestart` | Suppress reboot (pair with `--quiet` or `--passive`) |
| `--noWeb` | Fully offline — only use files in layout |
| `--add <WorkloadId>` | Add workload/component (repeatable) |
| `--remove <WorkloadId>` | Remove workload (modify only) |
| `--includeRecommended` | Add recommended components for all specified workloads |
| `--includeOptional` | Add optional + recommended components |
| `--layout <dir>` | Create/update offline layout |
| `--verify` | Check layout for missing/corrupt files |
| `--fix` | Verify + redownload bad files (needs internet) |
| `--clean <catalog>` | Remove old versions from layout |
| `--config <vsconfig>` | Use vsconfig file to define workloads |
| `--installPath <dir>` | Target install directory |

---

## Reference Links
- Command-line parameters: https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=visualstudio
- Create network layout: https://learn.microsoft.com/en-us/visualstudio/install/create-a-network-installation-of-visual-studio?view=visualstudio
- Deploy layout to clients: https://learn.microsoft.com/en-us/visualstudio/install/deploy-a-layout-onto-a-client-machine?view=visualstudio
- Workload IDs (Professional): https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-professional?view=visualstudio
- VS 2026 Release History: https://learn.microsoft.com/en-us/visualstudio/releases/2026/release-history
