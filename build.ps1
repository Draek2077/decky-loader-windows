<#
.SYNOPSIS
    Build Windows PluginLoader.exe + PluginLoader_noconsole.exe from upstream decky-loader.
.DESCRIPTION
    Clones (or reuses) the official SteamDeckHomebrew/decky-loader source at a pinned ref,
    builds the React frontend and the PyInstaller backend, and drops both exes into .\dist.
    Does NOT require administrator rights. Use install.ps1 to deploy the result.
.PARAMETER Ref
    Upstream git ref (tag/branch/commit) to build. Defaults to the contents of upstream.ref.
.EXAMPLE
    .\build.ps1                 # build the pinned upstream.ref version
    .\build.ps1 -Ref v3.2.4     # build a specific upstream tag
#>
[CmdletBinding()]
param(
    [string]$Ref,
    [string]$WorkDir,
    [string]$OutDir,
    [string]$UpstreamRepo = 'https://github.com/SteamDeckHomebrew/decky-loader.git'
)
$ErrorActionPreference = 'Stop'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $ScriptDir 'lib\common.ps1')
if (-not $WorkDir) { $WorkDir = Join-Path $ScriptDir '.build' }
if (-not $OutDir)  { $OutDir  = Join-Path $ScriptDir 'dist' }

if (-not $Ref) {
    $refFile = Join-Path $ScriptDir 'upstream.ref'
    if (Test-Path $refFile) { $Ref = (Get-Content $refFile -Raw).Trim() }
}
if (-not $Ref) { throw 'No upstream ref given and upstream.ref is missing/empty.' }
if ($Ref -match '^[0-9]') { $Ref = "v$Ref" }   # bare version (3.2.4) -> upstream tag form (v3.2.4)
Write-Step "Building decky-loader Windows binaries (upstream ref: $Ref)"

foreach ($t in 'git', 'node', 'npm', 'python') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        throw "Required tool '$t' not found in PATH. See README prerequisites."
    }
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$src = Join-Path $WorkDir 'decky-loader'
if (-not (Test-Path (Join-Path $src '.git'))) {
    Write-Step "Cloning upstream -> $src"
    Invoke-Native git clone --filter=blob:none $UpstreamRepo $src
}

Push-Location $src
try {
    Invoke-Native git fetch --all --tags --prune --force
    Invoke-Native git checkout --force $Ref
    if (Test-GitBranch $Ref) { Invoke-Native git reset --hard "origin/$Ref" }
    $commit = Get-Native git rev-parse --short HEAD
    Write-Step "Upstream checked out at $Ref ($commit)"
} finally { Pop-Location }

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    Write-Step 'Installing pnpm (npm global)'
    Invoke-Native npm install -g pnpm
}

Write-Step 'Building frontend (React)'
Push-Location (Join-Path $src 'frontend')
try {
    Invoke-Native pnpm install --frozen-lockfile --dangerously-allow-all-builds
    Invoke-Native pnpm run build
} finally { Pop-Location }

$venv = Join-Path $WorkDir 'buildenv'
$venvScripts = Join-Path $venv 'Scripts'
if (-not (Test-Path (Join-Path $venvScripts 'python.exe'))) {
    Write-Step 'Creating isolated Python build venv'
    Invoke-Native python -m venv $venv
}
$venvPython      = Join-Path $venvScripts 'python.exe'
$venvPoetry      = Join-Path $venvScripts 'poetry.exe'
$venvPyInstaller = Join-Path $venvScripts 'pyinstaller.exe'

Write-Step 'Installing build tooling (poetry + pyinstaller) into venv'
Invoke-Native $venvPython -m pip install -U pip 'poetry-dynamic-versioning[plugin]' poetry pyinstaller

Write-Step 'Building backend exes (PyInstaller: console + noconsole)'
Push-Location (Join-Path $src 'backend')
try {
    $env:POETRY_VIRTUALENVS_CREATE = 'false'
    Invoke-Native $venvPoetry install --no-interaction
    Invoke-Native $venvPyInstaller pyinstaller.spec --noconfirm
    $env:DECKY_NOCONSOLE = '1'
    try { Invoke-Native $venvPyInstaller pyinstaller.spec --noconfirm }
    finally { Remove-Item Env:\DECKY_NOCONSOLE -ErrorAction SilentlyContinue }
} finally {
    Remove-Item Env:\POETRY_VIRTUALENVS_CREATE -ErrorAction SilentlyContinue
    Pop-Location
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$dist = Join-Path $src 'backend\dist'
Copy-Item (Join-Path $dist 'PluginLoader.exe') $OutDir -Force
Copy-Item (Join-Path $dist 'PluginLoader_noconsole.exe') $OutDir -Force
Write-Step "Build complete. Output in $OutDir :"
Get-ChildItem (Join-Path $OutDir '*.exe') | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
