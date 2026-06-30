---
name: InstallShield InstallScript-MSI — deploy the inner MSI, not setup.exe
description: InstallShield InstallScript-MSI EXEs can't go silent (ResultCode -3); extract the cached inner MSI and deploy it directly, backfilling driver/cert side-effects in a wrapper.
type: feedback
originSessionId: f08d21e3-95b0-4c8b-8969-a20e79318f37
---
When a **local vendor EXE** (not in winget) is an **InstallShield InstallScript-MSI**, do NOT try to make `setup.exe` run silently. Deploy the inner MSI directly.

**Identify it:**
- `(Get-Item setup.exe).VersionInfo.OriginalFilename` reads `InstallShield Setup.exe`.
- Launching it writes `%TEMP%\{GUID}\Setup.INI` with `ScriptDriven=1`, a `ProductCode`, `PackageCode`, and `CacheFolder=Downloaded Installations`.

**Why setup.exe silent fails:** `setup.exe /s /v"/qn"` and even `setup.exe /s /f1<recorded.iss> /v"/qn"` return InstallShield `ResultCode=-3` ("required data not found in Setup.iss") in `setup.log` and roll the install back. The split-brain tell: the Windows Installer event log shows the **inner MSI completed successfully (status 0)** while the InstallScript engine still fails and removes the ARP registration, leaving orphaned files. Recording a `setup.iss` (`setup.exe /r /f1<path>` — note `/f1` must be glued to the path with no space, or the launcher just shows its usage dialog) does NOT fix this. Stop chasing the response file.

**Working approach (validated on GE EnerVista D&I Setup 12.1):**
1. Launch the EXE once → it caches the extracted MSI to `%LOCALAPPDATA%\Downloaded Installations\{PackageCode}\` (`<App>.msi` + a language `.ini`). That MSI installs cleanly via `msiexec /i … /qn` (registers ProductCode in ARP).
2. Diff the full install vs the bare MSI with a verbose log (`/l*v`). Driver/child installers that appear only as `FileCopy` with no `LaunchApp`/`CAQuietExec` were run by the **InstallScript engine, not the MSI** — the bare `/qn` install skips them. Backfill those in a wrapper.
3. Script DT wrapper `Install.ps1`:
   - Trust the vendor's driver code-signing certs into `LocalMachine\TrustedPublisher` so the driver install is silent under SYSTEM. Use the **.NET `X509Store` API**, NOT `Import-Certificate`/the `Cert:` PSDrive — under `-NoProfile`/SYSTEM the latter throws *"a drive with the name 'Cert' does not exist"* (intermittently, which is worse). Same applies to removal in uninstall.
   - `msiexec /i "<inner>.msi" /qn …`
   - Pre-stage drivers via `pnputil /add-driver *.inf /install`. Source them from a reference install with `pnputil /export-driver oemNN.inf <dir>` — that yields proper signed packages. RNDIS-style drivers ship `.inf` + `.cat` only (they ride Windows' in-box RNDIS `.sys`).
   - Detection: ProductCode reg key under **both** native and `WOW6432Node` Uninstall hives (32-bit MSIs land in WOW6432Node), `DisplayVersion -ge`.
4. Uninstall = `msiexec /x {ProductCode} /qn`. Leave the shared vendor certs/drivers in place.

**Reboot handling — sanctioned exception to "never `/norestart`" ([[SCCM MSI deployment pattern]]):** the standard rule is to ship `/qn` only and let SCCM read msiexec's 3010/1641 via the DT exit-code table. For a package that **installs drivers under SYSTEM**, override it: add `/norestart REBOOT=ReallySuppress` to the msiexec args so the MSI can't reboot a client mid-deploy, and have the wrapper itself `exit 3010` if msiexec or `pnputil` reports a pending reboot. This is the *only* case where suppressing the MSI's reboot is correct; plain-MSI apps keep the `/qn`-only rule.

**Why this matters:** validated end-to-end on EnerVista D&I 12.1 — a clean-baseline run of the wrapper produced exit 0, ARP v12.1, 2 GE certs trusted, 3 RNDIS drivers staged, detection = `Installed`. The setup.exe `/s` path never produced a clean install across multiple attempts.

**How to apply:** for any InstallShield InstallScript-MSI, skip straight to extracting the cached inner MSI (Phase 3d of sccm-deploy) instead of fighting `setup.exe` silent switches or recording `setup.iss`. Relates to [[Extract installer EXEs with 7zip when packaging]].
