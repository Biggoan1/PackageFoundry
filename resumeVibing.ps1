<#
.SYNOPSIS
    resumeVibing.ps1 - get back into the PackageFoundry flow after a break.

.DESCRIPTION
    A "where did I leave off" helper for FAFOLAB SCCM packaging. It:
      1. Reads the active config from CCM_Env.md (Mode is the master switch).
      2. In Full mode, connects to the site and surfaces the most recently
         touched applications + their deploy/distribution state.
      3. Lists the most recent install/uninstall logs under the Client Log Path.
      4. Nudges the local SCCM client to retrieve + evaluate machine policy so
         anything you just packaged shows up in Software Center right away.

    In Standalone mode the SCCM-side steps are skipped by design (the site
    fields in CCM_Env.md are N/A in that mode).

.PARAMETER RecentCount
    How many recent applications / logs to show. Default 5.

.PARAMETER SkipPolicyTrigger
    Don't trigger the machine policy retrieval cycle.

.EXAMPLE
    .\resumeVibing.ps1
    .\resumeVibing.ps1 -RecentCount 10
#>
[CmdletBinding()]
param(
    [int]$RecentCount = 5,
    [switch]$SkipPolicyTrigger
)

# Keep going on soft failures (missing console, no client, etc.) - this is a status helper.
$ErrorActionPreference = 'Continue'

function Write-Section { param([string]$Title) Write-Host ''; Write-Host "=== $Title ===" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "  [ok]   $m"   -ForegroundColor Green }
function Write-Warn2{ param([string]$m) Write-Host "  [warn] $m"   -ForegroundColor Yellow }
function Write-Info { param([string]$m) Write-Host "  $m" }

Write-Host ''
Write-Host '  ~~~ resuming the vibe ~~~  PackageFoundry' -ForegroundColor Magenta

# --- 1. Read CCM_Env.md ------------------------------------------------------
$envFile = Join-Path $PSScriptRoot 'CCM_Env.md'
if (-not (Test-Path $envFile)) {
    Write-Warn2 "CCM_Env.md not found next to this script ($envFile). Cannot read site config."
    return
}

$cfg = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*-\s*\*\*(?<k>[^*]+)\*\*\s*:\s*(?<v>.+?)\s*$') {
        $cfg[$matches.k.Trim()] = $matches.v.Trim()
    }
}

$Mode       = $cfg['Mode']
$Server     = $cfg['SCCM Server (FQDN)']
$SiteCode   = $cfg['Site Code']
$SourcePath = $cfg['Package Source Path']
$Collection = $cfg['Default Collection']
$LogPath    = $cfg['Client Log Path']
if (-not $LogPath) { $LogPath = 'C:\distrib\Logs' }

Write-Section 'Active configuration'
Write-Info ("Mode:        {0}" -f $Mode)
Write-Info ("Site:        {0} ({1})" -f $SiteCode, $Server)
Write-Info ("Sources:     {0}" -f $SourcePath)
Write-Info ("Collection:  {0}" -f $Collection)
Write-Info ("Log path:    {0}" -f $LogPath)

$IsFull = ($Mode -and $Mode.Trim().ToLower() -eq 'full')

# --- 2. Full-mode: site reachability + recent apps ---------------------------
if ($IsFull) {
    $module = 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'

    Write-Section 'Site connection'
    if (-not (Test-Path $module)) {
        Write-Warn2 "ConfigurationManager module not found. Is the Admin Console installed on this box?"
    } else {
        try {
            Import-Module $module -ErrorAction Stop
            if (-not (Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue)) {
                New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $Server -Scope Script -ErrorAction Stop | Out-Null
            }
            Write-Ok "Connected to $SiteCode`: ($Server)"

            # Sources share reachability
            if ($SourcePath) {
                if (Test-Path $SourcePath) { Write-Ok "Sources share reachable: $SourcePath" }
                else { Write-Warn2 "Sources share NOT reachable: $SourcePath" }
            }

            Push-Location "$SiteCode`:"
            try {
                Write-Section "Most recent applications (top $RecentCount)"
                $apps = Get-CMApplication -Fast -ErrorAction Stop |
                    Sort-Object DateLastModified -Descending |
                    Select-Object -First $RecentCount

                if (-not $apps) {
                    Write-Info "No applications found."
                } else {
                    $apps |
                        Select-Object @{n='Name';e={$_.LocalizedDisplayName}},
                                      @{n='Version';e={$_.SoftwareVersion}},
                                      @{n='Deployed';e={$_.IsDeployed}},
                                      @{n='DTs';e={$_.NumberOfDeploymentTypes}},
                                      @{n='LastModified';e={$_.DateLastModified}} |
                        Format-Table -AutoSize | Out-String | Write-Host

                    # Distribution state of the single most-recently-touched app
                    $latest = $apps | Select-Object -First 1
                    Write-Section ("Distribution status: {0}" -f $latest.LocalizedDisplayName)
                    $ds = Get-CMDistributionStatus -ErrorAction SilentlyContinue |
                        Where-Object { $_.SoftwareName -like "*$($latest.LocalizedDisplayName)*" }
                    if ($ds) {
                        foreach ($d in $ds) {
                            Write-Info ("Targeted={0}  Success={1}  InProgress={2}  Failed={3}" -f `
                                $d.Targeted, $d.NumberSuccess, $d.NumberInProgress, $d.NumberErrors)
                        }
                    } else {
                        Write-Info "No distribution status row found."
                    }
                }
            } finally { Pop-Location }
        } catch {
            Write-Warn2 "Could not query the site: $_"
        }
    }
} else {
    Write-Section 'Site connection'
    Write-Info "Standalone mode - skipping all SCCM-side checks (site fields are N/A)."
}

# --- 3. Recent install/uninstall logs ----------------------------------------
Write-Section "Recent package logs (top $RecentCount)"
if (Test-Path $LogPath) {
    $logs = Get-ChildItem -Path $LogPath -Filter *.log -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First $RecentCount
    if ($logs) {
        $logs |
            Select-Object @{n='Log';e={$_.Name}},
                          @{n='LastWrite';e={$_.LastWriteTime}},
                          @{n='KB';e={[math]::Round($_.Length/1KB,1)}} |
            Format-Table -AutoSize | Out-String | Write-Host
    } else {
        Write-Info "No .log files in $LogPath yet."
    }
} else {
    Write-Info "Log path does not exist yet: $LogPath"
}

# --- 4. Resume: trigger machine policy on the local client -------------------
Write-Section 'Resume: machine policy'
if ($SkipPolicyTrigger) {
    Write-Info "Skipped (-SkipPolicyTrigger)."
} elseif (-not $IsFull) {
    Write-Info "Standalone mode - not touching the SCCM client."
} else {
    try {
        Invoke-WmiMethod -Namespace root\ccm -Class SMS_Client -Name TriggerSchedule `
            -ArgumentList '{00000000-0000-0000-0000-000000000021}' -ErrorAction Stop | Out-Null
        Write-Ok "Machine Policy Retrieval & Evaluation cycle triggered."
    } catch {
        Write-Warn2 "Could not trigger machine policy (is the SCCM client installed here?): $_"
    }
}

Write-Host ''
Write-Host '  Back in the flow. Go build something.' -ForegroundColor Magenta
Write-Host ''
