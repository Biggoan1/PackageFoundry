---
name: SCCM packaging - include icons
description: Always attempt to add icons to SCCM applications when packaging
type: feedback
---

Always include icons when creating SCCM application packages. Use Set-CMApplication -IconLocationFile as part of every packaging script.

**Why:** User preference — icons show up in Software Center and improve the user experience.

**How to apply:**
- Extract from a local installed executable using [System.Drawing.Icon]::ExtractAssociatedIcon() when the app is installed on the admin/packaging machine
- Download from the vendor's official site (favicon, apple-touch-icon, or brand assets) when not installed locally
- Convert ICO to PNG using System.Drawing when needed (try sizes 256, 128, 64, 48, 32)
- Save icons to C:\Temp\SCCM-<AppName>\Icons\ and apply at the end of the Create-SCCMApp script
- All icons must be safe for work (SFW) - no suggestive imagery
- If the vendor SVG is available but no hosted PNG, render it using WPF: Add-Type PresentationCore/PresentationFramework, parse the path with [System.Windows.Media.Geometry]::Parse(), render via RenderTargetBitmap, save with PngBitmapEncoder
- If no icon source can be found after reasonable effort, note it and skip rather than blocking the deployment
