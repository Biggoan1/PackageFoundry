# Install the Configuration Manager client from a management point.
# Reads MP / site code from CCM_Env.md if not supplied as parameters.

[CmdletBinding()]
param(
    [string]$MP,
    [string]$SiteCode,
    [string[]]$ExtraArgs,
    [string]$EnvFile = (Join-Path $PSScriptRoot 'CCM_Env.md')
)

$ErrorActionPreference = 'Stop'

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Elevated)) {
    Write-Host 'ccmsetup.exe requires Administrator. Open elevated PowerShell and rerun.' -ForegroundColor Red
    exit 1
}

# Fill in missing args from CCM_Env.md
if ((-not $MP -or -not $SiteCode) -and (Test-Path $EnvFile)) {
    $raw = Get-Content $EnvFile -Raw
    $found = @{}
    foreach ($m in [regex]::Matches($raw, '(?m)^- \*\*(?<k>[^*]+)\*\*:\s*(?<v>.*)$')) {
        $found[$m.Groups['k'].Value.Trim()] = $m.Groups['v'].Value.Trim()
    }
    if (-not $MP) {
        $v = $found['SCCM Server (FQDN)']
        if ($v -and $v -ne '<TBD>' -and $v -ne 'N/A') { $MP = $v }
    }
    if (-not $SiteCode) {
        $v = $found['Site Code']
        if ($v -and $v -ne '<TBD>' -and $v -ne 'N/A') { $SiteCode = $v }
    }
}

if (-not $MP -or -not $SiteCode) {
    Write-Host 'Need -MP and -SiteCode (or a populated CCM_Env.md with Mode=Full).' -ForegroundColor Red
    Write-Host 'Example: .\Install-CCMClient.ps1 -MP sccm1.fafolab.net -SiteCode FU1' -ForegroundColor Yellow
    exit 1
}

$source = "\\$MP\SMS_$SiteCode\Client"
$setup  = Join-Path $source 'ccmsetup.exe'

Write-Host ''
Write-Host '=== SCCM Client Install ===' -ForegroundColor Cyan
Write-Host ('  MP:        {0}' -f $MP)
Write-Host ('  Site Code: {0}' -f $SiteCode)
Write-Host ('  Source:    {0}' -f $source)
Write-Host ''

if (-not (Test-Path $setup)) {
    Write-Host ('Cannot reach {0}' -f $setup) -ForegroundColor Red
    Write-Host 'Check that the MP is reachable, the SMS_<SITECODE> share is published, and the running account has access.' -ForegroundColor Red
    exit 1
}

# Skip if the client is already there
$svc = Get-Service -Name CcmExec -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host ('CcmExec service is already present (status: {0}).' -f $svc.Status) -ForegroundColor Yellow
    $resp = Read-Host 'Reinstall anyway? (y/N)'
    if ($resp -notmatch '^[Yy]') {
        Write-Host 'Aborted.'
        exit 0
    }
    if (-not ($ExtraArgs -contains '/forceinstall')) { $ExtraArgs = @($ExtraArgs) + '/forceinstall' }
}

$ccmArgs = @(
    "/mp:$MP",
    "/source:$source",
    "SMSSITECODE=$SiteCode",
    "SMSMP=$MP"
)
if ($ExtraArgs) { $ccmArgs += $ExtraArgs | Where-Object { $_ } }

Write-Host ('Launching: ccmsetup.exe {0}' -f ($ccmArgs -join ' '))
Write-Host ''
$p = Start-Process -FilePath $setup -ArgumentList $ccmArgs -PassThru -Wait
Write-Host ('ccmsetup.exe exited with code {0}' -f $p.ExitCode)

Write-Host ''
Write-Host 'ccmsetup hands off to the ccmsetup service which runs the install asynchronously.' -ForegroundColor Yellow
Write-Host 'Watch progress in real time:' -ForegroundColor Yellow
Write-Host '  Get-Content C:\Windows\ccmsetup\Logs\ccmsetup.log -Wait -Tail 20' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Install is complete when the log shows "CcmSetup is exiting with return code 0"' -ForegroundColor Yellow
Write-Host 'and the "Configuration Manager" applet appears in Control Panel.' -ForegroundColor Yellow
