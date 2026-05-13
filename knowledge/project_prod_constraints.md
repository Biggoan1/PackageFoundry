---
name: Prod environment constraints - 25H2 and JRE licensing
description: Prod runs Windows 25H2 (no VBScript) and cannot use Oracle JRE; all packages must accommodate both
type: project
originSessionId: 664a770e-2a03-4392-a261-784fdcc561da
---
Prod environment has two hard constraints that affect every SCCM package:

1. **Windows 25H2 removes VBScript** - packages cannot rely on `cscript`/`wscript` or `.vbs` files at install OR runtime. The `WScript.Shell` and `Scripting.FileSystemObject` COM objects (from wshom.ocx / scrrun.dll) still work from PowerShell on 25H2 - it's the vbscript language engine that's gone.

2. **Oracle JRE is not allowed** - license changes. Use **Azul Zulu JRE 25** instead (SCCM app `Azul Zulu JRE 25`, default install path `C:\Program Files\Zulu\zulu-25-jre\`). For Java apps, point shortcut/launcher args at this path rather than bundling a JRE.

**Why:** License compliance (Oracle) and Microsoft removing the VBScript engine from Windows 25H2.

**How to apply:** When packaging any app that ships with a `.vbs` installer or bundled Oracle JRE, port the install logic to PowerShell (use `Expand-Archive`, native `Start-Process msiexec`, and `WScript.Shell` COM for .lnk creation) and make Azul Zulu 25 a dependency instead of bundling Java. For SFX installers that run a post-extract VBS, extract the payload with 7zip and replace the VBS with a PowerShell port.
