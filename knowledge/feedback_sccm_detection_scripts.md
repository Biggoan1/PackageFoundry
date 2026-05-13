---
name: SCCM detection scripts - registry + no exit codes
description: Detection scripts must use registry-based version checks, not file existence; no exit statements
type: feedback
---

Use registry-based detection, not file/exe existence checks. Query the Uninstall hive and validate version with `-ge`.

**Why:** File checks are fragile across versions. Registry MSI entries are authoritative and version-comparable. Exit codes in detection scripts cause SCCM errors.

**How to apply:** Standard pattern for every Detect.ps1:
```powershell
$minVersion = [version]"x.x.x.x"
$displayName = "App Name"

$detected = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                           "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" `
    -ErrorAction SilentlyContinue |
    Get-ItemProperty |
    Where-Object { $_.DisplayName -like "*$displayName*" -and $_.DisplayVersion -and [version]$_.DisplayVersion -ge $minVersion } |
    Select-Object -First 1

if ($detected) { Write-Host "Installed" }
```
- No `exit` statements anywhere
- Check both 64-bit and WOW6432Node hives
- Use `-ge` so newer versions also satisfy detection
