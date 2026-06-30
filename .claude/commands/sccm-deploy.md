Package and deploy an application in SCCM/MECM end-to-end. Follow each phase in order. Arguments: `$ARGUMENTS` (app name, version, and any special instructions).

---

## Environment (FAFOLAB)

- **Site code:** FU1  
- **Site server:** sccm1.fafolab.net  
- **CM module:** `C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1`  
- **Sources share:** `\\sccm1\Sources\` (local: `D:\Sources\`)  
- **Distribution point:** SCCM1.fafolab.net  
- **Default target collection:** All Systems  
- All work runs via `New-PSSession -ComputerName sccm1.fafolab.net`; never use Get-Content -Raw in a remote session — join lines instead  

---

## Phase 1 — Identify the Installer

Run `winget show --id <PackageId> --source winget` and check the **Installer Type** field:

| Installer Type | Deployment approach |
|---|---|
| `wix` / `msi` | MSI — use msiexec directly (see Phase 3a) |
| `nullsoft` / `inno` / `burn` | EXE — use winget Script DT (see Phase 3b) |
| `portable` / `zip` | Portable — copy + PATH script (see Phase 3c) |
| InstallShield (local vendor EXE) | InstallScript-MSI — extract & deploy the inner MSI (see Phase 3d) |

Also note the **version**, **Installer URL**, and **Installer SHA256** for staging.

For a **local vendor EXE** that isn't in winget, check `(Get-Item setup.exe).VersionInfo.OriginalFilename`. If it reads `InstallShield Setup.exe` (and the launched setup writes a `Setup.INI` with `ScriptDriven=1`), it is an InstallScript-MSI — go to **Phase 3d**, and do not waste time recording a `setup.iss`.

---

## Phase 2 — Stage Content to sccm1

Folder convention: `D:\Sources\<App Name> <Version>\`

Sub-folders:
- `Scripts\` — Install + Uninstall PS1 files
- `Icons\` — PNG icon (invoke `/sccm-find-icon` for this)
- `Content\` — binaries only if portable/EXE; MSI goes in root

At the source-folder **root**, always ship two plain-text docs (full spec in **Phase 9**):
- `SCCM_Commands.txt` — copy/paste DT commands + the detection script **inline**
- `PACKAGING_NOTES.txt` — source, install logic, file manifest, logs, upgrade notes

Do **not** ship a separate `Detect.ps1` in the source folder — the detection script is embedded in the DT (Phase 5) and written inline into `SCCM_Commands.txt`. (A local Detect.ps1 is fine for authoring the `ScriptText`; just don't copy it to the source folder.)

Always use **PSSession + Copy-Item -ToSession** (never direct UNC writes):
```powershell
$s = New-PSSession -ComputerName sccm1.fafolab.net
Invoke-Command -Session $s -ScriptBlock { New-Item -ItemType Directory -Force -Path 'D:\Sources\<App> <Ver>\Scripts' | Out-Null }
Copy-Item 'C:\Temp\...\Install.ps1' -Destination 'D:\Sources\<App> <Ver>\Scripts\Install.ps1' -ToSession $s
```
Create `C:\Temp\` locally before any Copy-Item -ToSession operations.

---

## Phase 3a — MSI Deployment Type

**Get product code from MSI before writing scripts:**
```powershell
$db = (New-Object -ComObject WindowsInstaller.Installer).OpenDatabase($msiPath, 0)
$view = $db.OpenView("SELECT Value FROM Property WHERE Property = 'ProductCode'")
$view.Execute(); $view.Fetch().StringData(1)
```

**Install command** (no PS wrapper — direct msiexec):
```
msiexec.exe /i <filename>.msi /qn /norestart
```

**Uninstall command:**
```
msiexec.exe /x {PRODUCT-CODE-GUID} /qn /norestart
```

**Detection script** — product code GUID as registry key + DisplayVersion:
```powershell
$regPath    = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{PRODUCT-CODE-GUID}'
$minVersion = [version]'x.x.x'
$key = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
if ($key -and $key.DisplayVersion -and [version]$key.DisplayVersion -ge $minVersion) {
    Write-Output 'Installed'
}
```

**Deployment type settings:**
- `InstallationBehaviorType`: `InstallForSystem`
- `LogonRequirementType`: `WhetherOrNotUserLoggedOn`

---

## Phase 3b — Winget/EXE Script Deployment Type

Winget requires a logged-on user — SYSTEM cannot run winget.

**Winget path resolution** (always resolve dynamically):
```powershell
$WingetPath = Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
```

**Install script** (`Scripts\Install-<App>.ps1`):
```powershell
# (winget path resolution above)
if (-not $WingetPath) { Write-Error 'winget not found'; exit 1 }
& $WingetPath install --id <PackageId> --version <ver> --source winget --silent --accept-package-agreements --accept-source-agreements
exit $LASTEXITCODE
```
Do NOT use `--scope machine` — winget in user context is per-user only.

**Uninstall script:**
```powershell
# (winget path resolution above)
& $WingetPath uninstall --id <PackageId> --silent --accept-source-agreements
exit $LASTEXITCODE
```

**Detection script** — winget list check:
```powershell
$WingetPath = Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $WingetPath) { exit 1 }
$result = & $WingetPath list --id <PackageId> --source winget --accept-source-agreements 2>&1
if ($result -match '<PackageId escaped regex>') { Write-Output 'Installed' }
```

**Deployment type settings:**
- `InstallationBehaviorType`: `InstallForUser`
- `LogonRequirementType`: `OnlyWhenUserLoggedOn`

---

## Phase 3c — Portable Deployment Type

**Install script:**
```powershell
$destDir = 'C:\Program Files\<AppName>'
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot '..\Content\<app>.exe') -Destination "$destDir\<app>.exe" -Force
$currentPath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
if ($currentPath -notlike "*$destDir*") {
    [System.Environment]::SetEnvironmentVariable('PATH', "$currentPath;$destDir", 'Machine')
}
exit 0
```

**Detection script:**
```powershell
$exe        = 'C:\Program Files\<AppName>\<app>.exe'
$minVersion = [version]'x.x.x'
if (Test-Path $exe) {
    $ver = (& $exe --version 2>&1) -replace '[^0-9.]'
    if ([version]$ver -ge $minVersion) { Write-Output 'Installed' }
}
```
Adapt version parsing to the specific app's `--version` output format.

**Deployment type settings:**
- `InstallationBehaviorType`: `InstallForSystem`
- `LogonRequirementType`: `WhetherOrNotUserLoggedOn`

---

## Phase 3d — InstallShield InstallScript-MSI (extract the inner MSI)

Some vendor EXEs (usually local, not in winget — e.g. GE EnerVista) are **InstallShield InstallScript-MSI** packages. Identify per Phase 1 (`OriginalFilename` = `InstallShield Setup.exe`, `Setup.INI` has `ScriptDriven=1` + a `ProductCode`).

**These cannot be installed silently through `setup.exe`.** `setup.exe /s [/f1 recorded.iss] /v"/qn"` returns InstallShield `ResultCode=-3` (see `setup.log`) and rolls back — *even with a correctly recorded `setup.iss`*. The inner MSI itself installs fine; the InstallScript engine is what fails. Deploy the inner MSI directly instead.

1. **Get the MSI.** Launch the EXE once; it caches the extracted MSI to `%LOCALAPPDATA%\Downloaded Installations\{PackageCode}\` (per `Setup.INI` `CacheFolder=Downloaded Installations`). Grab the `.msi` (+ any `.ini`). ProductCode/Version come from `Setup.INI` or the MSI Property table.
2. **Diff full-install vs bare-MSI** with a verbose log (`/l*v`): a driver/child installer that shows only `FileCopy` and no matching `LaunchApp`/`CAQuietExec` means the **InstallScript ran it, not the MSI** — a bare `/qn` install will skip it. That diff is the wrapper's to-do list.
3. **Deploy as a Script DT** (not `Add-CMMsiDeploymentType`) when the install needs side-effects the MSI alone won't do (driver staging, cert trust, child MSIs). Wrapper `Install.ps1`:
   - Import vendor code-signing certs into `LocalMachine\TrustedPublisher` via **.NET `X509Store`** — NOT `Import-Certificate`/the `Cert:` PSDrive, which fails under `-NoProfile`/SYSTEM with *"a drive with the name 'Cert' does not exist"*.
   - `msiexec /i "<inner>.msi" /qn …` then pre-stage drivers with `pnputil /add-driver *.inf /install` (export them from a reference install via `pnputil /export-driver`; RNDIS-style drivers carry only `.inf` + `.cat`, no custom `.sys`).
   - Detection: ProductCode reg key under **both** native and `WOW6432Node` Uninstall, `DisplayVersion -ge`.

**Reboot note — the one sanctioned exception to the house "never `/norestart`" rule:** for a **SYSTEM-context driver install**, add `/norestart REBOOT=ReallySuppress` to the msiexec args so the MSI can't reboot a client mid-deploy, and have the wrapper return `3010` itself if any step reports a pending reboot. The plain-MSI rule (ship `/qn` only, let SCCM act on 3010/1641 via the DT exit-code table) still stands for everything else — this override is *only* for packages that install drivers under SYSTEM.

**Deployment type settings:**
- `InstallationBehaviorType`: `InstallForSystem`
- `LogonRequirementType`: `WhetherOrNotUserLoggedOn`

---

## Phase 4 — Detection Script Rules (all types)

- **No `exit` statements** anywhere in detection scripts — they cause SCCM errors
- Use `Write-Output 'Installed'` (not Write-Host) on successful detection
- Use `-ge` for version checks so newer versions satisfy detection
- For MSI: use product code GUID as the direct registry key, not DisplayName search
- For winget: use `winget list` check, not registry
- For portables: file existence + version parse

---

## Phase 5 — Create the SCCM Application (via PSSession)

Always pass detection script text as a parameter — never use Get-Content -Raw remotely:
```powershell
$detectText = (Get-Content 'C:\Temp\...\Detect-<App>.ps1') -join "`r`n"

Invoke-Command -Session $s -ArgumentList $detectText -ScriptBlock {
    param($detectText)
    Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'
    Set-Location FU1:

    New-CMApplication -Name '<App> <Ver>' -Publisher '<Publisher>' -SoftwareVersion '<Ver>' `
        -Description '<Description>' -LocalizedName '<App> <Ver>'

    Add-CMScriptDeploymentType `
        -ApplicationName    '<App> <Ver>' `
        -DeploymentTypeName '<type label>' `
        -ContentLocation    '\\sccm1\Sources\<App> <Ver>' `
        -InstallCommand     '<install cmd>' `
        -UninstallCommand   '<uninstall cmd>' `
        -ScriptLanguage     PowerShell `
        -ScriptText         $detectText `
        -InstallationBehaviorType <InstallForSystem|InstallForUser> `
        -LogonRequirementType     <WhetherOrNotUserLoggedOn|OnlyWhenUserLoggedOn> `
        -MaximumRuntimeMins 30 `
        -EstimatedRuntimeMins 10

    Set-CMApplication -Name '<App> <Ver>' -IconLocationFile '\\sccm1\Sources\<App> <Ver>\Icons\<App>.png'
}
```

---

## Phase 6 — Distribute Content

After creating the app, distribute content to the DP:
```powershell
Invoke-Command -Session $s -ScriptBlock {
    Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'
    Set-Location FU1:
    Start-CMContentDistribution -ApplicationName '<App> <Ver>' -DistributionPointName 'SCCM1.fafolab.net'
}
```

---

## Phase 7 — Create the Deployment

**Standard deployment** (Available to All Systems — default for this dev environment, always do this automatically after creating an app unless told otherwise):
```powershell
Invoke-Command -Session $s -ScriptBlock {
    Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'
    Set-Location FU1:
    New-CMApplicationDeployment `
        -Name                  '<App> <Ver>' `
        -CollectionName        'All Systems' `
        -DeployAction          Install `
        -DeployPurpose         Available `
        -UserNotification      DisplaySoftwareCenterOnly `
        -AvailableDateTime     (Get-Date)
}
```

**Required deployment** (use when the app must be installed):
```powershell
New-CMApplicationDeployment `
    -Name              '<App> <Ver>' `
    -CollectionName    '<Target Collection>' `
    -DeployAction      Install `
    -DeployPurpose     Required `
    -UserNotification  DisplaySoftwareCenterOnly `
    -AvailableDateTime (Get-Date) `
    -DeadlineDateTime  (Get-Date).AddDays(7)
```

**Deployment purpose guidance:**
- `Available` — user installs from Software Center on their own schedule; use for most apps
- `Required` — installs automatically by deadline; use for mandatory software/security tools

**UserNotification options:**
- `DisplaySoftwareCenterOnly` — show in Software Center, only notify for restarts (default for all deployments in this environment)
- `DisplayAll` — show toast notifications
- `HideAll` — fully silent, no Software Center entry

---

## Phase 8 — Verify and Wrap Up

1. Confirm content distribution status:
```powershell
Get-CMDistributionStatus -Name '<App> <Ver>'
```

2. Check the application was created correctly:
```powershell
Get-CMApplication -Name '<App> <Ver>' | Select-Object LocalizedDisplayName, SoftwareVersion, IsDeployed, NumberOfDeployments
```

3. **Always trigger machine policy on the local device as the final step:**
```powershell
Invoke-WMIMethod -Namespace root\ccm -Class SMS_Client -Name TriggerSchedule -ArgumentList '{00000000-0000-0000-0000-000000000021}'
```

---

## Phase 9 — Ship the package docs (NOT optional)

Every package source folder **must** contain two plain-text files at its root. Create them as part of the build (Phase 2 staging) and confirm they exist before reporting done — they are how the user rebuilds apps in the separate prod SCCM environment.

**`SCCM_Commands.txt`** — copy/paste-ready DT settings (plain text, no markdown/code fences):
- App name + content location + icon filename
- Install command (exact string) and Uninstall command (exact string)
- **Detection script contents inline**, between `----- begin detection script -----` / `----- end detection script -----` markers (do NOT ship a separate `Detect.ps1`)
- Install behavior (system/user), logon requirement, user experience, max/est run time, dependencies
- For MSI apps: ProductCode, DisplayVersion, install path
- Log file paths the wrapper writes
- A full copy-paste `New-CMApplication` / `Add-CMScriptDeploymentType` (or `Add-CMMsiDeploymentType`) rebuild block
- A short dated "Why <change>" note at the bottom for non-obvious choices

**`PACKAGING_NOTES.txt`** — the non-obvious context that isn't in the mechanical DT settings:
- Title line + `===` underline
- **Source** (vendor/URL/store id), **What this is**, **How it installs** (logic + context + caveats)
- **Files in this package** (file → purpose table), **Install logs** (paths), **Upgrade notes** (supersedence)

**HARD RULE:** any time a DT field changes (install/uninstall command, detection, install behavior, logon requirement, user experience, run time, dependencies, content location) — including one-off `Set-CMScriptDeploymentType`/`Set-CMMsiDeploymentType` tweaks — update `SCCM_Commands.txt` in the **same** operation and push it back to the source folder before reporting done.

---

## Troubleshooting Reference

| Symptom | Log to check | Common cause |
|---|---|---|
| Error 0x87D00324 | `AppDiscovery.log`, `AppEnforce.log` | Detection method wrong — app installed but not detected |
| Content not available | `DataTransferService.log`, `CAS.log` | Content not distributed to DP yet |
| Policy not received | `PolicyAgent.log` | Trigger Machine Policy cycle on client |
| Install fails silently | `AppEnforce.log` | Install command or working directory wrong |
| Detection returns nothing | `ScriptDiscovery.log` | Exit statement in detection script; remove it |

**Key client-side log locations:** `C:\Windows\CCM\Logs\`

**After fixing a detection method:** clients re-evaluate on next policy cycle without reinstalling the software.

---

## Supersedence (when updating an app to a new version)

1. Create the new version app as normal
2. Open the old app → Deployment Types → Properties → Supersedence tab → Add the new DT
3. Set "Uninstall superseded application" if needed
4. Deploy the new version — SCCM will automatically upgrade clients that have the old version

---

## Reference Links
- System Center Dudes: https://www.systemcenterdudes.com/
- Error 0x87D00324 fix: https://www.systemcenterdudes.com/fix-sccm-error-0x87d00324-when-deploying-applications/
- Dynamic query collections: https://www.systemcenterdudes.com/sccm-dynamic-queries/
- Disable a deployment: https://www.systemcenterdudes.com/quickly-disable-sccm-application-deployment/
