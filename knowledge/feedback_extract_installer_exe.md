---
name: Extract installer EXEs with 7zip when packaging
description: Many vendor installer .exe files are archives (RAR SFX, NSIS, InnoSetup, MSI wrappers) and can be extracted and repackaged to bypass embedded prompts
type: feedback
originSessionId: 664a770e-2a03-4392-a261-784fdcc561da
---
When a vendor ships an installer `.exe` that has problems (interactive prompts, VBScript dependencies, bundled Oracle JRE, no silent switch), try **extracting it with 7-Zip first** before resorting to dialog-clicking watchers or other hacks.

`"C:\Program Files\7-Zip\7z.exe" l <installer.exe>` will reveal the archive type (Rar5, NSIS, Inno, MSI, CAB, etc.) and often the post-extract Setup command baked into the SFX header. `7z x` extracts the payload without running the embedded setup.

Once extracted you can:
- Pre-stage the payload in the SCCM source folder
- Patch/replace problem scripts (e.g. remove a `MsgBox` from a .vbs)
- Port the setup logic to PowerShell directly (robocopy + shortcuts + config)
- Swap out bundled dependencies (e.g. replace bundled Oracle JRE by just not copying it and pointing at Azul)

**Why:** Proved out on Dell Avamar Administrator 19.4 — the "installer" was a RAR5 SFX whose Setup= command ran `cscript bin\create_shortcuts.vbs`, which showed an unconditional OpenSC Yes/No `MsgBox`. Extracting + porting to PowerShell was dramatically cleaner than trying to dismiss the dialog with Win32 button-click messages (which didn't reliably work anyway).

**How to apply:** Any time a vendor EXE installer is fighting you — interactive prompts, no silent mode, bundled deps you need to swap, vbscript dependencies on 25H2 — run `7z l` on it first. If it extracts cleanly, rebuild the install in PowerShell using the extracted payload as the source.
