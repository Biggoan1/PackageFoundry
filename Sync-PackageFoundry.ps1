<#
.SYNOPSIS
    Commits and pushes the PackageFoundry repo to GitHub on demand.

.DESCRIPTION
    Stages all changes (respecting .gitignore), commits, and pushes to
    origin/main. Run this whenever you want local changes to land on
    https://github.com/Biggoan1/PackageFoundry.

.PARAMETER Message
    Commit message. If omitted, a timestamped message is generated.

.EXAMPLE
    .\Sync-PackageFoundry.ps1
    .\Sync-PackageFoundry.ps1 -Message "Add Foo app package"
#>
[CmdletBinding()]
param(
    [string]$Message
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# Confirm this is the PackageFoundry repo
$remote = (git remote get-url origin 2>$null)
if ($remote -notmatch 'Biggoan1/PackageFoundry') {
    Write-Error "origin does not point at the PackageFoundry GitHub repo (got: $remote)"
    exit 1
}

# Pull any remote changes first to avoid a rejected push
Write-Host "Fetching origin..." -ForegroundColor Cyan
git fetch origin --quiet
$behind = (git rev-list --count HEAD..origin/main)
if ([int]$behind -gt 0) {
    Write-Host "Local is $behind commit(s) behind origin. Rebasing..." -ForegroundColor Yellow
    git pull --rebase origin main
}

# Stage everything (.gitignore excludes CCM_Env.md, .installed.flag, settings.local.json)
git add -A

$pending = (git status --porcelain)
$ahead   = [int](git rev-list --count origin/main..HEAD)

if (-not $pending -and $ahead -eq 0) {
    Write-Host "Nothing to sync - working tree clean and up to date with origin." -ForegroundColor Green
    exit 0
}

if ($pending) {
    if (-not $Message) {
        $Message = "Sync PackageFoundry - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    }
    Write-Host "Committing: $Message" -ForegroundColor Cyan
    git commit -m $Message
}
else {
    Write-Host "No new changes to commit, but local is ahead of origin - pushing existing commits." -ForegroundColor Yellow
}

Write-Host "Pushing to origin/main..." -ForegroundColor Cyan
git push origin main

Write-Host ""
Write-Host "Done. Repo synced to https://github.com/Biggoan1/PackageFoundry" -ForegroundColor Green
git status --short --branch
