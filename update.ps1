<#
.SYNOPSIS
    Update the installed Decky to a newer upstream version and redeploy.
.DESCRIPTION
    Resolves the latest upstream release tag (or uses -Ref), pins it in upstream.ref,
    rebuilds the exes, and redeploys them over the running install (with backup).
    This is how you recover when a Steam update breaks Decky: just run update.ps1.
.PARAMETER Ref
    Explicit upstream ref to build. Default: latest upstream stable release.
.PARAMETER Prerelease
    When auto-resolving, allow the newest prerelease instead of the latest stable.
.EXAMPLE
    .\update.ps1                  # update to latest upstream stable
    .\update.ps1 -Prerelease      # update to newest upstream prerelease
    .\update.ps1 -Ref v3.2.5-pre1 # update to a specific tag
#>
[CmdletBinding()]
param(
    [string]$Ref,
    [switch]$Prerelease,
    [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

if (-not $Ref) {
    Write-Step 'Resolving latest upstream release tag from GitHub'
    $headers = @{ 'User-Agent' = 'decky-loader-windows' }
    if ($Prerelease) {
        $Ref = (Invoke-RestMethod 'https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases' -Headers $headers)[0].tag_name
    } else {
        $Ref = (Invoke-RestMethod 'https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases/latest' -Headers $headers).tag_name
    }
}
if (-not $Ref) { throw 'Could not resolve an upstream ref.' }
Write-Step "Updating to upstream ref: $Ref"
Write-TextFileNoBom -Path (Join-Path $PSScriptRoot 'upstream.ref') -Content $Ref

# Build (no admin), then deploy via install.ps1 -NoBuild (self-elevates for deploy only).
& (Join-Path $PSScriptRoot 'build.ps1') -Ref $Ref

$installArgs = @('-Ref', $Ref, '-NoBuild')
if ($NoStart) { $installArgs += '-NoStart' }
& (Join-Path $PSScriptRoot 'install.ps1') @installArgs
