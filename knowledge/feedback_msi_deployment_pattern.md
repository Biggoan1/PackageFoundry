---
name: SCCM MSI deployment pattern
description: Use Add-CMMsiDeploymentType (Windows Installer DT type) for MSI installers; do not wrap msiexec in cmd or PowerShell.
type: feedback
originSessionId: dc3ef9fa-cb09-4ee6-84fb-370bdb06f4a2
---
For SCCM applications backed by an MSI, use the **native Windows Installer deployment type** (`Add-CMMsiDeploymentType`), NOT a script DT that runs msiexec, and NEVER a cmd.exe wrapper.

The proper invocation:

```powershell
Add-CMMsiDeploymentType `
    -ApplicationName 'App Name' `
    -DeploymentTypeName 'App Name <version> (MSI)' `
    -ContentLocation '\\sccm1\Sources\...\filename.msi' `
    -ProductCode '{GUID-FROM-MSI-PROPERTY-TABLE}' `
    -InstallationBehaviorType InstallForSystem `
    -LogonRequirementType WhetherOrNotUserLoggedOn `
    -UserInteractionMode Hidden `
    -MaximumRuntimeMins 15 `
    -EstimatedRuntimeMins 1 `
    -Force
```

Key details:

- **`-ContentLocation` points at the MSI file itself**, not the folder. The cmdlet errors with "Unexpected file extension specified. Must be one of: .msi" if you point at a folder.
- **Do NOT pass `-InstallCommand` / `-UninstallCommand` to `Add-CMMsiDeploymentType`**. Let it auto-derive from the MSI + ProductCode (it produces `msiexec /i "filename.msi" /q` and `msiexec /x {ProductCode} /q`). Passing custom commands at create time seems to make the cmdlet fall through to a script-typed DT.
- **After creation, override the install/uninstall commands with `Set-CMMsiDeploymentType -InstallCommand / -UninstallCommand`** to enforce house style. Set-* keeps the DT as Technology=MSI (verified). House style is **always `/qn`** (explicit "no UI") and **never `/norestart`** - let SCCM see msiexec's natural exit codes (1641 / 3010) and determine reboot behavior via the DT's RebootExitCodes / HardRebootExitCodes table. Adding `/norestart` overrides that decision.

  ```powershell
  Set-CMMsiDeploymentType `
      -ApplicationName 'App Name' `
      -DeploymentTypeName 'App Name 1.0 (MSI)' `
      -InstallCommand   'msiexec /i "filename.msi" /qn' `
      -UninstallCommand 'msiexec /x {ProductCode} /qn'
  ```
- **`-ProductCode` creates the Windows Installer detection rule automatically**. ProductCode is unique per MSI build, so version match is implicit. No need for a custom registry-based detection script unless you want a tolerant `DisplayVersion -ge X` rule.
- **Verify the result** by checking `Technology` in the SDMPackageXML - it must read `MSI`, not `Script`. If it reads `Script`, the cmdlet didn't create what you wanted.
- **`-MaximumRuntimeMins` minimum is 15** for `Add-CMMsiDeploymentType` AND `Add-CMScriptDeploymentType`. Anything below 15 throws "argument is less than the minimum allowed range of 15". Floor at 15 even for tiny installs.
- **Logs**: do NOT add `/l*v "C:\distrib\Logs\..."` to the install command. AppEnforce.log on the client captures the msiexec invocation and exit code. For verbose MSI logging, set the system-wide policy in `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer\Logging = "voicewarmupx"`.

**Read the ProductCode from the MSI Property table** under Win PS 5.1 (the COM object's IDispatch is friendlier there than in PS7's reflection):

```powershell
$installer = New-Object -ComObject WindowsInstaller.Installer
$db   = $installer.OpenDatabase($MsiPath, 0)
$view = $db.OpenView('SELECT Property, Value FROM Property')
$view.Execute()
$out = @{}
while ($rec = $view.Fetch()) { $out[$rec.StringData(1)] = $rec.StringData(2) }
$out['ProductCode'], $out['ProductVersion']
```

**Why:** Confirmed 2026-05-05 packaging CMTrace Open. First attempt used `Add-CMScriptDeploymentType` with a `cmd.exe /c "if not exist C:\distrib\Logs mkdir ... & msiexec /i ..."` wrapper. The `if/&` parsing trap (separate memory) caused exit 0 in 50ms with msiexec never running. Second attempt with `Add-CMMsiDeploymentType -InstallCommand <custom>` produced a Script DT with a stale install command. Third attempt - omitting `-InstallCommand` and letting the cmdlet auto-derive - finally produced a real MSI DT (Technology=MSI, install command `msiexec /i "..." /q`) which installed cleanly: registry key created, files in place.

**How to apply:** Use this pattern for every MSI app from now on. Don't reach for `Add-CMScriptDeploymentType` to wrap msiexec - the MSI DT is the correct primitive. Reserve script DTs for non-MSI installers (raw EXE, PowerShell, custom).
