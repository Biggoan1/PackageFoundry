Find and download the best available icon for an SCCM application package. Follow this priority order and stop at the first success:

## Priority Order

**1. Installed app on local machine**
Check common install paths for the app executable. If found, extract with:
```powershell
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
$bmp = $icon.ToBitmap()
$bmp.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png)
```
Common paths to check:
- `$env:ProgramFiles\<Vendor>\<App>\<App>.exe`
- `$env:LOCALAPPDATA\Programs\<App>\<App>.exe`
- `$env:LOCALAPPDATA\<Vendor>\<App>.exe`

**2. Installer EXE product icon (via winget manifest)**
Run `winget show --id <PackageId> --source winget` and parse the installer URL from the output. Download the installer EXE to `C:\Temp\icon-extract\`, extract the embedded icon, then delete the installer. Many installers embed the app's product icon even when the app is not installed.
```powershell
$wingetOutput = & $WingetPath show --id $PackageId --source winget
# Parse the "Installer Url:" line
$installerUrl = ($wingetOutput | Where-Object { $_ -match 'Installer Url' }) -replace '.*Installer Url:\s*',''
Invoke-WebRequest -Uri $installerUrl -OutFile $installerExe -UseBasicParsing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($installerExe)
# ... save as PNG, then Remove-Item $installerExe
```

**3. Microsoft Store (for Store-sourced winget packages)**
If the winget package ID is a 13-character alphanumeric Store ID (e.g. `9NBLGGH4NNS1`), try the undocumented Store API:
```powershell
$uri = "https://apps.microsoft.com/store/api/ProductsDetails/GetProductDetailsById/$StoreId?hl=en-US&gl=US"
$details = Invoke-RestMethod -Uri $uri -UseBasicParsing
$iconUrl = $details.IconUrl
Invoke-WebRequest -Uri $iconUrl -OutFile $outPng -UseBasicParsing
```
Also try: `https://storeedgefd.dsx.mp.microsoft.com/v9.0/packageManifests/$StoreId` for metadata that may include icon info.

**4. Vendor website**
Fetch the app's homepage and look for high-resolution image assets in this order:
- `<link rel="apple-touch-icon">` (typically 180x180)
- `<meta property="og:image">` (varies, often large)
- `/apple-touch-icon.png` at the root
- `/favicon.ico` (last resort — convert ICO→PNG via System.Drawing)

```powershell
$html = (Invoke-WebRequest -Uri $homepageUrl -UseBasicParsing).Content
$touchIcon = [regex]::Match($html, 'apple-touch-icon[^>]*href="([^"]+)"').Groups[1].Value
$ogImage   = [regex]::Match($html, 'og:image[^>]*content="([^"]+)"').Groups[1].Value
```

**5. SVG → PNG via WPF**
If the only available asset is an SVG (e.g. from a GitHub repo's `.github/logo.svg`), render it to PNG using WPF:
```powershell
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
$geo = [System.Windows.Media.Geometry]::Parse($svgPathData)
$drawing = New-Object System.Windows.Media.GeometryDrawing
$drawing.Geometry = $geo
$drawing.Brush = New-Object System.Windows.Media.SolidColorBrush($brandColor)
$drawingGroup = New-Object System.Windows.Media.DrawingGroup
$drawingGroup.Transform = New-Object System.Windows.Media.ScaleTransform(($size/248.0), ($size/248.0))
$drawingGroup.Children.Add($drawing)
$image = New-Object System.Windows.Media.DrawingImage($drawingGroup)
$visual = New-Object System.Windows.Media.DrawingVisual
$ctx = $visual.RenderOpen()
$ctx.DrawImage($image, [System.Windows.Rect]::new(0,0,$size,$size))
$ctx.Close()
$bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($size,$size,96,96,[System.Windows.Media.PixelFormats]::Pbgra32)
$bitmap.Render($visual)
$enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
$enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
$stream = [System.IO.File]::OpenWrite($outPng)
$enc.Save($stream); $stream.Close()
```

## ICO → PNG Conversion
When converting ICO files, try the largest available size:
```powershell
foreach ($size in @(256,128,64,48,32)) {
    try { $icon = New-Object System.Drawing.Icon($icoPath, $size, $size); break } catch {}
}
$bmp = $icon.ToBitmap()
$bmp.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png)
```

## Output
- Save the final icon to `C:\Temp\SCCM-<AppName>\Icons\<AppName>.png`
- Target resolution: 256x256 minimum
- All icons must be safe for work (SFW)
- After finding the icon, apply it: `Set-CMApplication -Name "<AppName>" -IconLocationFile $iconPath`
- If no icon can be found after all steps, report what was tried and continue without blocking the deployment
