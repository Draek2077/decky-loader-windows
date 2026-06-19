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
    [string]$WorkDir = (Join-Path $PSScriptRoot '.build'),
    [string]$OutDir  = (Join-Path $PSScriptRoot 'dist'),
    [string]$UpstreamRepo = 'https://github.com/SteamDeckHomebrew/decky-loader.git'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

if (-not $Ref) {
    $refFile = Join-Path $PSScriptRoot 'upstream.ref'
    if (Test-Path $refFile) { $Ref = (Get-Content $refFile -Raw).Trim() }
}
if (-not $Ref) { throw 'No upstream ref given and upstream.ref is missing/empty.' }
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
    git clone --filter=blob:none $UpstreamRepo $src
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed.' }
}

Push-Location $src
try {
    git fetch --all --tags --prune --force | Out-Null
    git checkout --force $Ref
    if ($LASTEXITCODE -ne 0) { throw "git checkout '$Ref' failed." }
    git reset --hard "origin/$Ref" 2>$null   # fast-forward branches; harmless for tags
    $commit = (git rev-parse --short HEAD).Trim()
    Write-Step "Upstream checked out at $Ref ($commit)"
} finally { Pop-Location }

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    Write-Step 'Installing pnpm (npm global)'
    npm install -g pnpm
    if ($LASTEXITCODE -ne 0) { throw 'pnpm install failed.' }
}

Write-Step 'Building frontend (React)'
Push-Location (Join-Path $src 'frontend')
try {
    pnpm install --frozen-lockfile --dangerously-allow-all-builds
    if ($LASTEXITCODE -ne 0) { throw 'pnpm install (frontend) failed.' }
    pnpm run build
    if ($LASTEXITCODE -ne 0) { throw 'frontend build failed.' }
} finally { Pop-Location }

$venv = Join-Path $WorkDir 'buildenv'
$venvScripts = Join-Path $venv 'Scripts'
if (-not (Test-Path (Join-Path $venvScripts 'python.exe'))) {
    Write-Step 'Creating isolated Python build venv'
    python -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw 'venv creation failed.' }
}
Write-Step 'Installing build tooling (poetry + pyinstaller) into venv'
& (Join-Path $venvScripts 'python.exe') -m pip install -U pip 'poetry-dynamic-versioning[plugin]' poetry pyinstaller
if ($LASTEXITCODE -ne 0) { throw 'pip install of build tooling failed.' }

Write-Step 'Building backend exes (PyInstaller: console + noconsole)'
Push-Location (Join-Path $src 'backend')
try {
    $env:POETRY_VIRTUALENVS_CREATE = 'false'
    & (Join-Path $venvScripts 'poetry.exe') install --no-interaction
    if ($LASTEXITCODE -ne 0) { throw 'poetry install (backend) failed.' }
    try { & (Join-Path $venvScripts 'poetry.exe') dynamic-versioning 2>&1 | Out-Null } catch { }
    & (Join-Path $venvScripts 'pyinstaller.exe') pyinstaller.spec --noconfirm
    if ($LASTEXITCODE -ne 0) { throw 'pyinstaller (console) failed.' }
    $env:DECKY_NOCONSOLE = '1'
    & (Join-Path $venvScripts 'pyinstaller.exe') pyinstaller.spec --noconfirm
    $rc = $LASTEXITCODE
    Remove-Item Env:\DECKY_NOCONSOLE -ErrorAction SilentlyContinue
    if ($rc -ne 0) { throw 'pyinstaller (noconsole) failed.' }
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
