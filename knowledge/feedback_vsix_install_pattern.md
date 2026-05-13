---
name: VSIX install pattern (Visual Studio extensions)
description: Always pass /q to VSIXInstaller.exe; deploy DT as InstallForUser + OnlyWhenUserLoggedOn; detect per-user via $env:LOCALAPPDATA.
type: feedback
originSessionId: dc3ef9fa-cb09-4ee6-84fb-370bdb06f4a2
---
For SCCM packages that deploy a Visual Studio `.vsix` extension, follow this pattern.

**Always pass `/q` to VSIXInstaller.exe** for both install AND uninstall. Without `/q` the installer shows interactive UI dialogs even when launched from SCCM as SYSTEM or as the user, which fails silent-deploy expectations.

```powershell
# Install (per-user; default - no /admin):
Start-Process $vsixInstaller -ArgumentList "/q `"$vsixPath`"" -Wait -PassThru

# Uninstall (per-user):
Start-Process $vsixInstaller -ArgumentList "/q /uninstall:$ExtensionGuid" -Wait -PassThru
```

**Discover VS instances with `vswhere.exe`, not `MSFT_VSInstance`.** vswhere ships with the VS Installer at `C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe` and is authoritative:

- Default output is **complete + launchable** instances only. MSFT_VSInstance returns broken / "not in launchable state" instances too, which causes confusing downstream errors.
- `vswhere -requires <componentId> [<componentId> ...]` filters to instances with all listed workload components - lets you front-load prereq validation instead of waiting for VSIXInstaller to throw `NoApplicableSKUsException`.
- Returns rich JSON: `displayName`, `installationPath`, `installationVersion`, `productId`, `instanceId`, `isLaunchable`, etc.

Walk every VSIX manifest's `Prerequisites:` block when packaging - those component IDs go into your `-requires` filter so the script skips and logs unsupported instances cleanly:

```powershell
$Required = @(
    'Microsoft.VisualStudio.Component.Web',             # from VSIX manifest
    'Microsoft.VisualStudio.Component.TextTemplating'   # from VSIX manifest
)

$vsWhere  = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'

$allInst  = @((& $vsWhere -products '*' -format json -nologo) | ConvertFrom-Json)
$reqInst  = @((& $vsWhere -products '*' -requires $Required -format json -nologo) | ConvertFrom-Json)

# Log every instance: OK or SKIP-with-missing-ids
foreach ($i in $allInst) {
    $ok = $reqInst.instanceId -contains $i.instanceId
    if ($ok) {
        Write-Host "OK   $($i.displayName) [$($i.installationVersion)]"
    } else {
        $pkg = (& $vsWhere -instanceId $i.instanceId -include packages -format json -nologo) | ConvertFrom-Json
        if ($pkg -is [array]) { $pkg = $pkg[0] }
        $missing = $Required | Where-Object { $_ -notin @($pkg.packages.id) }
        Write-Host "SKIP $($i.displayName) [$($i.installationVersion)] - missing: $($missing -join ', ')"
    }
}

# Then iterate $reqInst (filter SSMS belt-and-suspenders) and call VSIXInstaller per instance:
foreach ($vs in ($reqInst | Where-Object { $_.displayName -notlike '*SQL Server Management Studio*' })) {
    $vsixInstaller = Join-Path $vs.installationPath 'Common7\IDE\VSIXInstaller.exe'
    if (Test-Path $vsixInstaller) {
        # call /q + path as above
    }
}
```

If `vswhere.exe` is genuinely missing, fall back to `Get-CimInstance MSFT_VSInstance -Namespace root/cimv2/vs` and project to the same shape (`displayName`, `installationPath`, `instanceId`) - but warn loudly that prereq validation is skipped in that mode.

**Deploy the DT as `InstallForUser` + `OnlyWhenUserLoggedOn`.** VSIXInstaller without `/admin` installs per-user into `%LOCALAPPDATA%\Microsoft\VisualStudio\<vsId>\Extensions\`. Running it as SYSTEM drops files into SYSTEM's profile (where no real user's VS will see them) and forces detection to glob `C:\Users\*` to find anything. Use `Add-CMScriptDeploymentType -InstallationBehaviorType InstallForUser -LogonRequirementType OnlyWhenUserLoggedOn`. (Use `/admin` only if you actually want to install for all users in the machine-wide VS folder, which is rare.)

**Detection script under user context** uses `$env:LOCALAPPDATA` directly. Cover both per-user (typical) and system-wide (admin-installed) locations:

```powershell
$guid = '<extension-id-guid>'
$found = $false

# System-wide VS extensions (admin-installed via VSIXInstaller /admin)
foreach ($vs in @(Get-CimInstance MSFT_VSInstance -Namespace root/cimv2/vs -ErrorAction SilentlyContinue)) {
    $extDir = Join-Path $vs.InstallLocation 'Common7\IDE\Extensions'
    if (Test-Path $extDir) {
        $hit = Get-ChildItem -Path $extDir -Recurse -Filter 'extension.vsixmanifest' -ErrorAction SilentlyContinue |
            Select-String -SimpleMatch -Quiet -Pattern $guid
        if ($hit) { $found = $true; break }
    }
}

# Current-user VS extension store (typical per-user VSIX install)
if (-not $found -and $env:LOCALAPPDATA) {
    $userExt = Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio'
    if (Test-Path $userExt) {
        $hit = Get-ChildItem -Path $userExt -Recurse -Filter 'extension.vsixmanifest' -ErrorAction SilentlyContinue |
            Select-String -SimpleMatch -Quiet -Pattern $guid
        if ($hit) { $found = $true }
    }
}

if ($found) { Write-Output 'Installed' }
```

Per `feedback_sccm_detection_scripts.md`: no `exit` statements; just `Write-Output 'Installed'` on success.

**Common exit codes from VSIXInstaller** to handle in install scripts:

| Code | Meaning | Treat as |
|---|---|---|
| 0 | success | success |
| 1001 | already installed | success on install |
| 2003 | extension not found | success on uninstall |
| 3010 | reboot required | reboot (let SCCM see it) |

Don't suppress 3010 with a custom `/norestart` equivalent; let SCCM's exit-code table determine reboot behavior.

**Why:** Confirmed 2026-05-06 troubleshooting Telerik UI for Blazor VS Extension. Original DT was InstallForSystem with no `/q`, which caused (a) VSIXInstaller GUI dialogs even under SCCM, (b) installation into SYSTEM's profile invisible to real users, (c) detection forced to enumerate `C:\Users\*\AppData\Local\Microsoft\VisualStudio\` to compensate. Flipping to InstallForUser + OnlyWhenUserLoggedOn + `/q` made the install silent, correct, and detectable via plain `$env:LOCALAPPDATA`.

**`VSIXInstaller.NoApplicableSKUsException` debugging order**: when the dd_VSIXInstaller_*.log shows `Found setup instance <id> but not in launchable state` followed by `NoApplicableSKUsException`, the failure is NOT a SKU/edition mismatch despite what the exception name suggests. Order of likely causes:

1. **Paused VS Installer Modify operation** (most common - 2026-05-06 case). User clicks Pause in VS Installer mid-Modify, forgets, the install is left half-applied. Have them open VS Installer; if there is a "Resume" button, that's it. Verify after with `vswhere -all -property isLaunchable instanceId` - paused install reports `isLaunchable: False`.
2. **Crashed / interrupted Modify** - same end state, fix is VS Installer -> More -> Repair on that instance.
3. **Wrong edition** (Community/Enterprise vs Pro, or VS 2026 vs the VSIX's `[17.0,18.0)` range). Confirm with `vswhere -property productId installationVersion`.
4. **Missing prereq workload components** - only fires after the SKU check passes; would normally show different error text. Front-load this check with `vswhere -requires <componentIds>` in the install script anyway.

The component checkmarks visible in VS Installer reflect target state, not applied state. A paused Modify will show all the desired checkboxes ticked while the actual instance is still in `not launchable` because reconciliation never finished.

**How to apply:** New VSIX packages start from this template. When inheriting a VSIX package that's not silent or that globs `C:\Users\*` in detection, the fix is the same three pieces: add `/q`, flip context to user, switch detection to `$env:LOCALAPPDATA`.
