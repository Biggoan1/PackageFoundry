---
name: running on the site server = operate locally
description: When PackageFoundry runs ON the SCCM site server itself, use the local CM drive + local D:\Sources; do NOT use New-PSSession/UNC (they fail under the ssh-key logon)
type: feedback
---

PackageFoundry can run in two topologies: (a) on a separate packaging **workstation** that drives the site server remotely, or (b) directly **ON the site server** (moved there 2026-07-27). Detect which by comparing `$env:COMPUTERNAME` / the local FQDN against the **SCCM Server (FQDN)** in `CCM_Env.md`.

**When running ON the site server, operate LOCALLY — the remote patterns FAIL:**

- Do NOT `New-PSSession -ComputerName <site server>` (loopback). Under the usual SSH **key** logon (a network logon with no delegatable credentials) it fails with `0x8009030e "a specified logon session does not exist"`. Instead run all ConfigMgr cmdlets **in-process**: `Import-Module` the `ConfigurationManager.psd1`, then use the site-code CM drive (e.g. `FU1:`) directly. It connects to the local SMS provider via WMI (`root\SMS\site_<code>`) and works. Direct WMI (`Get-WmiObject -Namespace root\SMS\site_<code> ...`) also works.
- Do NOT stage content over the `\\<server>\Sources` UNC and do NOT use `Copy-Item -ToSession`. Copy files **directly to the local path** `D:\Sources\<App> <Ver>\...` (plain `New-Item`/`Copy-Item`). The deployment type's **ContentLocation** still uses the `\\<server>\Sources` UNC — that is just the DP source pointer to the same folder; only the agent's file WRITES must be local.

(The workstation topology still uses remote sessions — the sibling note `feedback_sccm1_remote_ps_limitations.md` applies in that case.)

**Why:** After PackageFoundry moved onto SCCM1, a `/sccm-deploy` that used the old `New-PSSession -ComputerName sccm1` pattern failed at connect (`0x8009030e`). Switching to the local CM drive + local `D:\Sources` let the VLC test package → distribute → deploy end-to-end (verified 2026-07-27).

**How to apply:** At the start of any Full-mode SCCM work, check whether this host IS the site server; if so, skip PSSession/UNC and use the local CM drive + local Sources path.
