# PackageFoundry

A portable Claude Code agent for packaging and deploying applications via Microsoft Configuration Manager (SCCM/MECM).

> **Project home (coming soon)**: https://github.com/Biggoan1/PackageFoundry
> Once published, future releases of `Bootstrap-PackageFoundry.ps1` will be available there, and an optional download-from-GitHub mode will replace the self-embedded payload approach. Until then, hand off `Bootstrap-PackageFoundry.ps1` directly.

## What this is

A self-contained folder that, when opened with Claude Code, loads:

- **CCM_Env.md** — your SCCM site details (server, site code, sources share, defaults)
- **knowledge/** — packaging conventions, detection-script patterns, log paths, prod constraints, lessons learned
- **.claude/commands/** — slash commands:
  - `/sccm-deploy` — end-to-end app packaging + deployment
  - `/sccm-find-icon` — pull the best icon for a package
  - `/vs-layout` — Visual Studio layout repos + SCCM deploy

## Install

1. Copy the entire `PackageFoundry` folder to the new machine (anywhere; `C:\PackageFoundry\` is fine).
2. Open **PowerShell as Administrator** in that folder. Admin is required so winget can install Node.js / Git / 7-Zip if they aren't already present.
3. Run:

   ```powershell
   .\Install-PackageFoundry.ps1
   ```

   The installer will:
   - Install **Node.js LTS**, **Git**, and **7-Zip** via winget if any are missing.
   - Install **Claude Code** via `npm install -g @anthropic-ai/claude-code`.
   - Prompt for any blank fields in `CCM_Env.md` (server FQDN, site code, sources share, etc.) and write them.

4. After it finishes, open a fresh PowerShell window (so the new PATH is loaded) and run:

   ```powershell
   cd <PackageFoundry folder>
   claude
   ```

   Sign in with the recipient's own Claude account on first run.

## Prerequisites the installer expects

- **Windows 10 1809+ or Windows 11** with `winget` available (App Installer from the Microsoft Store).
- **Administrator rights** on first run (only needed to install Node.js / Git / 7-Zip / Claude Code).
- Re-running later (after everything is installed) does not require admin and just re-prompts for any blank `CCM_Env.md` fields.

## Operating modes

The installer asks for **Mode** first:

- **Full** — PackageFoundry builds the package AND imports it into SCCM (creates the application, deployment type, content distribution, deployment to the default collection, and triggers machine policy). Requires SCCM Server, Site Code, Sources Directory, and a Default Collection.
- **Standalone** — PackageFoundry builds the package source folder, scripts, detection, `SCCM_Commands.txt`, and `PACKAGING_NOTES.txt` — but does **not** connect to or import into SCCM. Use this when you want to hand off the package to someone else, or when the machine running it isn't the SCCM admin box.

Switching modes later: edit `CCM_Env.md`, set `Mode` to the new value, blank out (`<TBD>`) any field you want re-prompted, and rerun `Install-PackageFoundry.ps1`.

## Helper: install the SCCM client on a target machine

`Install-CCMClient.ps1` runs `ccmsetup.exe` from the MP share to bootstrap the Configuration Manager client. It pulls MP / site code from `CCM_Env.md` if they're populated, or accepts them as parameters:

```powershell
# Use values from CCM_Env.md (Full mode):
.\Install-CCMClient.ps1

# Or override:
.\Install-CCMClient.ps1 -MP sccm1.example.net -SiteCode ABC

# Force reinstall, or pass any other ccmsetup arg:
.\Install-CCMClient.ps1 -ExtraArgs '/forceinstall'
```

Run as Administrator. After ccmsetup hands off to the service, tail `C:\Windows\ccmsetup\Logs\ccmsetup.log` to watch the install finish.

## Updating the environment

Either edit `CCM_Env.md` directly, or clear a value (set it to `<TBD>`) and rerun `Install-PackageFoundry.ps1` to be prompted for it.

## Pre-configured Claude Code permissions

PackageFoundry ships with `.claude/settings.json` containing a sensible allowlist so Claude isn't pestering you with permission prompts on every tool call. Scope:

- **Read / Glob / Grep / Task* / ToolSearch / WebSearch** — broad allow (read-only or coordination-only).
- **PowerShell / Bash** — broad allow (this is an SCCM packaging agent; it needs to run cmdlets, msiexec, vswhere, etc.).
- **Edit / Write** — scoped to local paths (`C:\distrib\`, the PackageFoundry folder itself, your Claude memory and commands folders, `C:\Windows\Temp\` / `C:\Temp\`). The shipped baseline contains **no UNC site paths** — those are added per-recipient by `Install-PackageFoundry.ps1` after you supply your SCCM server FQDN.
- **WebFetch** — scoped to known-good vendor domains: patchmypc.com, github.com, nodejs.org, *.microsoft.com, *.visualstudio.com, powershellgallery.com, nuget.org.

When you run the installer, it pulls the SCCM Server (FQDN) value from `CCM_Env.md` and appends UNC allow entries to `.claude/settings.json` for that server (both short and FQDN forms, covering `\\<server>\Sources\` and `\\<server>\SMS_*\`). Re-running the bootstrap refreshes the baseline + re-injects from your CCM_Env values.

To add additional one-off allowances on your machine, create `.claude/settings.local.json` next to the shipped `settings.json` — local file isn't shipped/overwritten by re-runs of the bootstrap.

To remove or tighten any defaults, edit `.claude/settings.json` directly.

## What is not included

- Authentication. The recipient signs into Claude with their own account.
- SCCM console / ConfigurationManager.psd1 module — install the SCCM Admin Console separately.
