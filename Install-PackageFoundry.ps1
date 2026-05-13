# PackageFoundry installer
# Bootstraps a fresh Windows box: installs Node.js, Git, 7-Zip, Claude Code,
# then prompts for SCCM site config and writes CCM_Env.md.

[CmdletBinding()]
param(
    [string]$AgentRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

if (-not $AgentRoot -or -not (Test-Path $AgentRoot)) {
    $AgentRoot = (Get-Location).Path
}

Write-Host ''
Write-Host '=== PackageFoundry Installer ===' -ForegroundColor Cyan
Write-Host ('Agent root: {0}' -f $AgentRoot)
Write-Host ''

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        [scriptblock]$AlreadyInstalled
    )
    if ($AlreadyInstalled -and (& $AlreadyInstalled)) {
        Write-Host ('      {0}: already installed' -f $Label) -ForegroundColor Green
        return
    }
    Write-Host ('      {0}: installing via winget ({1})...' -f $Label, $Id)
    & winget install --id $Id --exact --silent `
        --accept-package-agreements --accept-source-agreements `
        --disable-interactivity
    $code = $LASTEXITCODE
    # 0 ok, -1978335189 (0x8A15002B) "no upgrade available", -1978335212 (0x8A150014) "already installed"
    if ($code -ne 0 -and $code -ne -1978335189 -and $code -ne -1978335212) {
        Write-Host ('      winget exited with code {0} for {1}' -f $code, $Id) -ForegroundColor Yellow
    }
    Update-SessionPath
}

# ----- Phase 1: prerequisites ---------------------------------------------
Write-Host '[1/7] Checking prerequisites...' -ForegroundColor Cyan

$nodeOk   = [bool](Get-Command node -ErrorAction SilentlyContinue)
$gitOk    = [bool](Get-Command git  -ErrorAction SilentlyContinue)
$sevenZipExe = 'C:\Program Files\7-Zip\7z.exe'
$sevenOk  = Test-Path $sevenZipExe

$missing = @()
if (-not $nodeOk)  { $missing += 'Node.js' }
if (-not $gitOk)   { $missing += 'Git' }
if (-not $sevenOk) { $missing += '7-Zip' }

if ($missing.Count -gt 0) {
    if (-not (Test-Elevated)) {
        Write-Host ''
        Write-Host ('Need to install: {0}' -f ($missing -join ', ')) -ForegroundColor Yellow
        Write-Host 'These require Administrator rights. Open PowerShell as Administrator and rerun this script.' -ForegroundColor Yellow
        Write-Host ''
        exit 1
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host ''
        Write-Host 'winget is not available on this machine.' -ForegroundColor Red
        Write-Host 'Install "App Installer" from the Microsoft Store, then rerun this script.' -ForegroundColor Red
        Write-Host ''
        exit 1
    }

    if (-not $nodeOk) {
        Install-WingetPackage -Id 'OpenJS.NodeJS.LTS' -Label 'Node.js LTS' `
            -AlreadyInstalled { [bool](Get-Command node -ErrorAction SilentlyContinue) }
    } else {
        Write-Host '      Node.js: already installed' -ForegroundColor Green
    }

    if (-not $gitOk) {
        Install-WingetPackage -Id 'Git.Git' -Label 'Git' `
            -AlreadyInstalled { [bool](Get-Command git -ErrorAction SilentlyContinue) }
    } else {
        Write-Host '      Git: already installed' -ForegroundColor Green
    }

    if (-not $sevenOk) {
        Install-WingetPackage -Id '7zip.7zip' -Label '7-Zip' `
            -AlreadyInstalled { Test-Path $sevenZipExe }
    } else {
        Write-Host '      7-Zip: already installed' -ForegroundColor Green
    }

    Update-SessionPath
} else {
    Write-Host '      Node.js: already installed' -ForegroundColor Green
    Write-Host '      Git: already installed' -ForegroundColor Green
    Write-Host '      7-Zip: already installed' -ForegroundColor Green
}

# ----- Phase 2: Claude Code -----------------------------------------------
Write-Host ''
Write-Host '[2/7] Checking Claude Code...' -ForegroundColor Cyan
$claude = Get-Command claude -ErrorAction SilentlyContinue
if ($claude) {
    Write-Host ('      found: {0}' -f $claude.Source) -ForegroundColor Green
} else {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        Write-Host '      npm is not on PATH.' -ForegroundColor Red
        Write-Host '      Open a fresh PowerShell window (so the new PATH is loaded) and rerun this script.' -ForegroundColor Red
        exit 1
    }
    Write-Host '      installing @anthropic-ai/claude-code via npm...'
    & npm install -g '@anthropic-ai/claude-code'
    if ($LASTEXITCODE -ne 0) {
        Write-Host '      npm install failed.' -ForegroundColor Red
        exit 1
    }
    Update-SessionPath
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if ($claude) {
        Write-Host ('      installed: {0}' -f $claude.Source) -ForegroundColor Green
    } else {
        Write-Host '      installed, but not visible on the current session PATH. Open a new shell after this script finishes.' -ForegroundColor Yellow
    }
}

# ----- Phase 3: CCM_Env.md ------------------------------------------------
Write-Host ''
Write-Host '[3/7] SCCM environment configuration...' -ForegroundColor Cyan
$envPath = Join-Path $AgentRoot 'CCM_Env.md'
$existing = @{}
if (Test-Path $envPath) {
    $raw = Get-Content $envPath -Raw
    foreach ($m in [regex]::Matches($raw, '(?m)^- \*\*(?<k>[^*]+)\*\*:\s*(?<v>.*)$')) {
        $k = $m.Groups['k'].Value.Trim()
        $v = $m.Groups['v'].Value.Trim()
        if ($v -and $v -ne '<TBD>' -and $v -notmatch '^_+$') {
            $existing[$k] = $v
        }
    }
}

function Get-EnvValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [string]$Default
    )
    if ($script:existing.ContainsKey($Key)) {
        Write-Host ('      {0}: {1}  (kept)' -f $Key, $script:existing[$Key]) -ForegroundColor DarkGray
        return $script:existing[$Key]
    }
    $hint = if ($Default) { " [$Default]" } else { '' }
    $val = Read-Host ('      {0}{1}' -f $Key, $hint)
    if (-not $val -and $Default) { $val = $Default }
    while (-not $val) {
        $val = Read-Host ('      {0} (required)' -f $Key)
    }
    return $val
}

function Get-EnvChoice {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string[]]$Choices,
        [string]$Default
    )
    if ($script:existing.ContainsKey($Key)) {
        $v = $script:existing[$Key]
        if ($Choices -contains $v) {
            Write-Host ('      {0}: {1}  (kept)' -f $Key, $v) -ForegroundColor DarkGray
            return $v
        }
    }
    $list = $Choices -join '/'
    $hint = if ($Default) { " [$Default]" } else { '' }
    while ($true) {
        $val = Read-Host ('      {0} ({1}){2}' -f $Key, $list, $hint)
        if (-not $val -and $Default) { $val = $Default }
        if ($Choices -contains $val) { return $val }
        Write-Host ('      must be one of: {0}' -f $list) -ForegroundColor Yellow
    }
}

$mode = Get-EnvChoice -Key 'Mode' -Choices @('Full','Standalone') -Default 'Full'

if ($mode -eq 'Full') {
    $server     = Get-EnvValue -Key 'SCCM Server (FQDN)'
    $siteCode   = Get-EnvValue -Key 'Site Code'
    $sourcePath = Get-EnvValue -Key 'Package Source Path'
    $sourcesDir = Get-EnvValue -Key 'Sources Directory (server-local)' -Default 'D:\Sources'
    $collection = Get-EnvValue -Key 'Default Collection' -Default 'All Systems'
} else {
    Write-Host '      Standalone mode: skipping SCCM-specific fields.' -ForegroundColor DarkGray
    $server     = 'N/A'
    $siteCode   = 'N/A'
    $sourcePath = Get-EnvValue -Key 'Package Source Path' -Default 'C:\Packages'
    $sourcesDir = 'N/A'
    $collection = 'N/A'
}
$arch    = Get-EnvValue -Key 'Default Architecture' -Default 'x64'
$logPath = Get-EnvValue -Key 'Client Log Path' -Default 'C:\distrib\Logs'

$envContent = @"
# CCM Environment

Active configuration for the SCCM site this agent operates against.
Edit values directly if the environment changes; rerun Install-SCCMAgent.ps1 to fill blanks.

``Mode`` is the master switch:
- **Full** - build the package AND import it into SCCM.
- **Standalone** - build the package only; do not touch SCCM. The SCCM site fields are not used in this mode.

- **Mode**: $mode
- **SCCM Server (FQDN)**: $server
- **Site Code**: $siteCode
- **Package Source Path**: $sourcePath
- **Sources Directory (server-local)**: $sourcesDir
- **Default Collection**: $collection
- **Default Architecture**: $arch
- **Client Log Path**: $logPath
"@

Set-Content -Path $envPath -Value $envContent -Encoding UTF8
Write-Host ('      wrote {0}' -f $envPath) -ForegroundColor Green

# ----- Phase 4: scrub author's lab-specific defaults ----------------------
# The shipped kit carries the author's real site values (FAFOLAB / sccm1 /
# FU1 / D:\Sources) as a working reference. On first install we substitute
# them with the values just collected in Phase 3 so the agent's context
# reflects THIS environment, not the author's. Idempotent via a marker file.
Write-Host ''
Write-Host '[4/7] Scrubbing author defaults from kit content...' -ForegroundColor Cyan
$scrubFlag = Join-Path $AgentRoot '.installed.flag'
if (Test-Path $scrubFlag) {
    Write-Host '      already scrubbed (marker present) - skipping' -ForegroundColor DarkGray
} elseif ($mode -eq 'Standalone' -or -not $server -or $server -eq 'N/A') {
    Write-Host '      Standalone mode - skipping (no site values to substitute)' -ForegroundColor DarkGray
} else {
    $serverShort = ($server -split '\.')[0]
    $serverParts = $server -split '\.'
    $labShort = if ($serverParts.Count -ge 2) { $serverParts[1].ToUpper() } else { 'LAB' }

    # Ordered: longest / most-specific patterns first so they win over bare tokens.
    $pairs = @(
        @{ From = 'FAFOLAB\administrator';      To = ('{0}\administrator' -f $labShort) },
        @{ From = 'sccm1.fafolab.net';          To = $server },
        @{ From = 'SCCM1.fafolab.net';          To = $server },
        @{ From = '\\sccm1\Sources';            To = ('\\{0}\Sources' -f $serverShort) },
        @{ From = '//sccm1/Sources';            To = ('//{0}/Sources' -f $serverShort) },
        @{ From = '\\sccm1\';                   To = ('\\{0}\' -f $serverShort) },
        @{ From = '//sccm1/';                   To = ('//{0}/' -f $serverShort) },
        @{ From = 'sccm1';                      To = $serverShort },
        @{ From = 'SCCM1';                      To = $serverShort.ToUpper() },
        @{ From = 'FAFOLAB';                    To = $labShort },
        @{ From = 'FU1';                        To = $siteCode },
        @{ From = 'D:\Sources';                 To = $sourcesDir }
    )

    $targets = @()
    $targets += Join-Path $AgentRoot 'CLAUDE.md'
    $targets += Join-Path $AgentRoot 'Install-CCMClient.ps1'
    $targets += Join-Path $AgentRoot '.claude\settings.json'
    $kDir = Join-Path $AgentRoot 'knowledge'
    if (Test-Path $kDir) {
        $targets += (Get-ChildItem -LiteralPath $kDir -Filter *.md -File).FullName
    }
    $cDir = Join-Path $AgentRoot '.claude\commands'
    if (Test-Path $cDir) {
        $targets += (Get-ChildItem -LiteralPath $cDir -Filter *.md -File).FullName
    }

    $touched = 0
    foreach ($path in $targets) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $orig = Get-Content -LiteralPath $path -Raw
        if ($null -eq $orig) { continue }
        $text = $orig
        foreach ($p in $pairs) {
            $text = $text.Replace($p.From, $p.To)
        }
        if ($text -ne $orig) {
            Set-Content -LiteralPath $path -Value $text -Encoding UTF8 -NoNewline
            $touched++
            Write-Host ('        scrubbed: {0}' -f $path.Substring($AgentRoot.Length).TrimStart('\')) -ForegroundColor DarkGray
        }
    }

    Set-Content -LiteralPath $scrubFlag -Value (Get-Date -Format 'o') -Encoding UTF8
    Write-Host ('      scrubbed {0} file(s); FAFOLAB->{1}, sccm1->{2}, FU1->{3}' -f $touched, $labShort, $serverShort, $siteCode) -ForegroundColor Green
    Write-Host ('      marker:    {0}' -f $scrubFlag) -ForegroundColor DarkGray
}

# ----- Phase 5: inject site UNC paths into Claude permissions -------------
Write-Host ''
Write-Host '[5/7] Adding site UNC paths to Claude permissions...' -ForegroundColor Cyan
$settingsPath = Join-Path $AgentRoot '.claude\settings.json'
if (-not (Test-Path $settingsPath)) {
    Write-Host '      settings.json not found - skipping' -ForegroundColor Yellow
} elseif (-not $server -or $server -eq 'N/A' -or $server -eq '<TBD>') {
    Write-Host '      Standalone mode (no SCCM server) - skipping site-path injection'
} else {
    try {
        $shortName = ($server -split '\.')[0]
        $hostNames = @($shortName, $server) | Sort-Object -Unique
        $newAllows = foreach ($h in $hostNames) {
            ('Edit(//{0}/Sources/**)'  -f $h)
            ('Edit(//{0}/SMS_*/**)'    -f $h)
            ('Write(//{0}/Sources/**)' -f $h)
            ('Write(//{0}/SMS_*/**)'   -f $h)
        }

        $json = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        if (-not $json.permissions)         { $json | Add-Member permissions ([pscustomobject]@{ allow = @() }) -Force }
        if (-not $json.permissions.allow)   { $json.permissions | Add-Member allow @() -Force }
        $existing = @($json.permissions.allow)
        $added = @()
        foreach ($entry in $newAllows) {
            if ($existing -notcontains $entry) { $existing += $entry; $added += $entry }
        }
        $json.permissions.allow = $existing
        ($json | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $settingsPath -Encoding UTF8

        if ($added.Count -gt 0) {
            Write-Host ('      added {0} entries for {1}:' -f $added.Count, ($hostNames -join ' / '))
            $added | ForEach-Object { Write-Host ('        + {0}' -f $_) -ForegroundColor DarkGray }
        } else {
            Write-Host ('      entries for {0} already present' -f ($hostNames -join ' / '))
        }
    } catch {
        Write-Host ('      failed: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        Write-Host '      (non-fatal; you can add UNC allow entries manually to .claude\settings.json)'
    }
}

# ----- Phase 6: layout sanity check ---------------------------------------
Write-Host ''
Write-Host '[6/7] Verifying PackageFoundry layout...' -ForegroundColor Cyan
$expected = @(
    'CLAUDE.md',
    '.claude\commands\sccm-deploy.md',
    '.claude\commands\sccm-find-icon.md',
    '.claude\commands\vs-layout.md',
    'knowledge'
)
$missingFiles = @()
foreach ($rel in $expected) {
    if (-not (Test-Path (Join-Path $AgentRoot $rel))) { $missingFiles += $rel }
}
if ($missingFiles.Count -gt 0) {
    Write-Host '      missing files:' -ForegroundColor Red
    $missingFiles | ForEach-Object { Write-Host ('        {0}' -f $_) -ForegroundColor Red }
    exit 1
}
$kCount = (Get-ChildItem (Join-Path $AgentRoot 'knowledge') -Filter *.md -File).Count
Write-Host ('      knowledge files: {0}' -f $kCount) -ForegroundColor Green
Write-Host '      layout OK' -ForegroundColor Green

# ----- Phase 7: desktop shortcut ------------------------------------------
Write-Host ''
Write-Host '[7/7] Creating PackageFoundry desktop shortcut...' -ForegroundColor Cyan
try {
    # All Users desktop so every account on this box sees it
    $desktopDir = [Environment]::GetFolderPath('CommonDesktopDirectory')
    if (-not $desktopDir) { $desktopDir = [Environment]::GetFolderPath('Desktop') }
    $lnkPath  = Join-Path $desktopDir 'PackageFoundry.lnk'
    $iconPath = Join-Path $AgentRoot 'PackageFoundry.ico'

    # Prefer pwsh.exe if PS7 is available; otherwise Windows PowerShell 5.1
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $shellExe = if ($pwsh) { $pwsh.Source } else { "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" }

    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnkPath)
    $sc.TargetPath       = $shellExe
    $sc.Arguments        = ('-NoExit -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath ''{0}''; claude"' -f $AgentRoot)
    $sc.WorkingDirectory = $AgentRoot
    $sc.Description      = 'PackageFoundry - SCCM packaging assistant (Claude Code)'
    $sc.WindowStyle      = 1   # Normal window
    if (Test-Path $iconPath) {
        $sc.IconLocation = "$iconPath,0"
    }
    $sc.Save()
    Write-Host ('      created: {0}' -f $lnkPath) -ForegroundColor Green
    Write-Host ('      target : {0}' -f $shellExe)
    if (Test-Path $iconPath) { Write-Host ('      icon   : {0}' -f $iconPath) }
} catch {
    Write-Host ('      shortcut creation failed: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
    Write-Host '      (non-fatal; run claude from the install folder manually)'
}

Write-Host ''
Write-Host '=== Done ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'To launch PackageFoundry:'
Write-Host '  - Double-click the desktop shortcut, OR' -ForegroundColor Yellow
Write-Host ('  - cd "{0}" ; claude' -f $AgentRoot) -ForegroundColor Yellow
Write-Host ''
Write-Host 'On first run, sign in with the Claude account this machine will use.'
Write-Host ''
