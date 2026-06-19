<#
.SYNOPSIS
    Full Windows install of Decky Loader - replaces the ACCESS-DENIIED installer entirely.
.DESCRIPTION
    Builds the exes (unless -NoBuild), then performs the complete install the way the
    third-party installer would, but from current upstream source:
      * creates the ~/homebrew folder tree and a default loader.json
      * enables Steam CEF remote debugging (the flag Decky needs to inject)
      * backs up any existing exes and deploys the freshly built ones
      * registers the elevated run-at-logon autostart scheduled task
      * disables the legacy Startup-folder shortcut if present
      * starts Decky (unless -NoStart)
    Requires administrator rights; self-elevates with a UAC prompt if needed.
.EXAMPLE
    .\install.ps1                 # build pinned ref + full install
    .\install.ps1 -NoBuild        # deploy whatever is already in .\dist
    .\install.ps1 -Ref v3.2.4     # build a specific upstream tag, then install
#>
[CmdletBinding()]
param(
    [string]$Ref,
    [switch]$NoBuild,
    [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $ScriptDir 'lib\common.ps1')

# Build first (does not need admin), THEN elevate only for the deploy steps.
$dist = Join-Path $ScriptDir 'dist'
if (-not $NoBuild) {
    & (Join-Path $ScriptDir 'build.ps1') -Ref $Ref
    $NoBuild = $true   # already built; don't rebuild after elevation
}

if (-not (Test-Admin)) {
    Invoke-SelfElevate -ScriptPath (Join-Path $ScriptDir 'install.ps1') -BoundParameters @{ Ref = $Ref; NoBuild = [switch]$true; NoStart = $NoStart }
    return
}

$noconsole = Join-Path $dist 'PluginLoader_noconsole.exe'
if (-not (Test-Path $noconsole)) {
    throw "Built exes not found in $dist. Run build.ps1 first, or drop -NoBuild."
}

$homebrew = Get-HomebrewPath
$services = Join-Path $homebrew 'services'

Write-Step "Creating homebrew folder tree at $homebrew"
foreach ($d in 'plugins', 'services', 'settings', 'themes', 'logs', 'data') {
    New-Item -ItemType Directory -Force -Path (Join-Path $homebrew $d) | Out-Null
}
$loaderJson = Join-Path $homebrew 'settings\loader.json'
if (-not (Test-Path $loaderJson)) {
    Write-TextFileNoBom -Path $loaderJson -Content '{ "branch": 0, "pluginOrder": [] }'
    Write-Step 'Wrote default loader.json (stable branch)'
}

$steam = Get-SteamPath
$cefFlag = Join-Path $steam '.cef-enable-remote-debugging'
if (-not (Test-Path $cefFlag)) {
    Write-Step "Enabling Steam CEF remote debugging ($cefFlag)"
    New-Item -ItemType File -Path $cefFlag -Force | Out-Null
} else {
    Write-Step 'Steam CEF remote debugging already enabled'
}

Write-Step 'Stopping any running Decky instance'
Stop-DeckyTask

foreach ($exe in 'PluginLoader.exe', 'PluginLoader_noconsole.exe') {
    $target = Join-Path $services $exe
    if (Test-Path $target) {
        $bakDir = Join-Path $homebrew ('services_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
        New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
        Copy-Item $target $bakDir -Force
        Write-Step "Backed up existing $exe -> $bakDir"
    }
}
Write-Step "Deploying new exes to $services"
Copy-Item (Join-Path $dist 'PluginLoader.exe') $services -Force
Copy-Item $noconsole $services -Force

Write-Step "Registering elevated autostart task '$DeckyTaskName' (at logon, highest privileges)"
Register-DeckyTask -ExePath (Join-Path $services 'PluginLoader_noconsole.exe')

$legacy = Join-Path ([Environment]::GetFolderPath('Startup')) 'Decky Loader.lnk'
if (Test-Path $legacy) {
    Move-Item $legacy (Join-Path $homebrew 'Decky Loader (legacy startup - disabled).lnk') -Force
    Write-Step 'Disabled legacy non-elevated Startup-folder shortcut'
}

if (-not $NoStart) {
    Start-ScheduledTask -TaskName $DeckyTaskName
    Write-Step 'Decky started.'
}
Write-Step 'Install complete. Fully restart Steam, then open the Quick Access menu to see the Decky icon.'
