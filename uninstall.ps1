<#
.SYNOPSIS
    Stop Decky and remove the autostart task. Optionally purge all Decky data.
.PARAMETER Purge
    Also delete the ~/homebrew folder (plugins, settings, logs) and remove the
    Steam CEF remote-debugging flag. Destructive - your plugins/settings are lost.
.EXAMPLE
    .\uninstall.ps1            # stop + remove autostart, keep data
    .\uninstall.ps1 -Purge     # full removal
#>
[CmdletBinding()]
param([switch]$Purge)
$ErrorActionPreference = 'Stop'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $ScriptDir 'lib\common.ps1')

if (-not (Test-Admin)) {
    Invoke-SelfElevate -ScriptPath (Join-Path $ScriptDir 'uninstall.ps1') -BoundParameters $PSBoundParameters
    return
}

Write-Step 'Stopping Decky'
Stop-DeckyTask

if (Get-ScheduledTask -TaskName $DeckyTaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $DeckyTaskName -Confirm:$false
    Write-Step "Removed scheduled task '$DeckyTaskName'"
}

if ($Purge) {
    $homebrew = Get-HomebrewPath
    if (Test-Path $homebrew) {
        Remove-Item $homebrew -Recurse -Force
        Write-Step "Removed $homebrew"
    }
    try {
        $cef = Join-Path (Get-SteamPath) '.cef-enable-remote-debugging'
        if (Test-Path $cef) { Remove-Item $cef -Force; Write-Step 'Removed Steam CEF debug flag' }
    } catch { }
}

Write-Step 'Uninstall complete.'
