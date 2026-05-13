---
name: Winget SCCM packaging pattern
description: Standard scripts and conventions for packaging winget-sourced apps into SCCM
type: project
originSessionId: 28b76f76-692b-4d1c-a586-796ae4521e09
---
**Pattern:** Use winget as the installer engine inside Install.ps1/Uninstall.ps1, wrapped as a Script deployment type in SCCM.

**Content path:** `\\sccm1\Sources\<Vendor>\<AppName>\winget\`
(no version subfolder since winget always installs latest)

**Key implementation details:**

- **Winget requires a logged-on user context — SYSTEM cannot access winget.** Deployment type must use `InstallForUser` / `OnlyWhenUserLoggedOn`, NOT `InstallForSystem`.
- `--scope machine` must NOT be used; winget in user context installs per-user.
- **Do NOT resolve winget via `Get-Item "$env:ProgramFiles\WindowsApps\..."`** — `C:\Program Files\WindowsApps` denies directory listing to standard users, so wildcard enumeration fails in user context. Use the app execution alias (on every user's PATH) with an `AppxPackage` fallback:
  ```powershell
  $WingetPath = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
  if (-not $WingetPath) {
      $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
          Sort-Object Version -Descending | Select-Object -First 1
      if ($pkg -and $pkg.InstallLocation) {
          $candidate = Join-Path $pkg.InstallLocation 'winget.exe'
          if (Test-Path $candidate) { $WingetPath = $candidate }
      }
  }
  if (-not $WingetPath) { exit 1 }
  ```
- Install flags: `--silent --accept-source-agreements --accept-package-agreements`
- Exit code `-1978335212` (0x8A150014) = already installed (treat as success on install, not-installed on uninstall)
- Detection: prefer `Get-AppxPackage -Name "<PackageName>"` for Store/MSIX apps (works in user context with no path resolution needed). If you must use `winget list`, reuse the resolution block above.

**Create-SCCMApp.ps1 note:** Read Detect.ps1 using local D:\ path (not UNC) and avoid `-Raw`:
```powershell
$DetectScript = (Get-Content "D:\Sources\...\Detect.ps1") -join "`r`n"
```

**Why:** NVIDIA Control Panel (winget ID: `NVIDIA.NVIDIAControlPanel`) was packaged this way successfully on 2026-03-27. Pattern is reusable for any winget-available app.

**How to apply:** Use this structure for any app where the vendor provides no silent MSI/EXE and the app is available via winget.
