# Shared helpers for decky-loader-windows scripts.
# Dot-source this from the entry scripts: . (Join-Path $PSScriptRoot 'lib\common.ps1')

$script:DeckyTaskName = 'Decky Loader'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[decky] $Message" -ForegroundColor Cyan
}

function Get-HomebrewPath {
    # Decky's data root on Windows.
    Join-Path $env:USERPROFILE 'homebrew'
}

function Get-SteamPath {
    try {
        $p = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        if ($p) { return ($p -replace '/', '\') }
    } catch { }
    $fallback = 'C:\Program Files (x86)\Steam'
    if (Test-Path $fallback) { return $fallback }
    throw 'Could not locate the Steam install path (registry + default both missing).'
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Relaunch the calling script elevated, forwarding its bound parameters.
function Invoke-SelfElevate {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [hashtable]$BoundParameters = @{}
    )
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ScriptPath))
    foreach ($kv in $BoundParameters.GetEnumerator()) {
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($kv.Value.IsPresent) { $parts += "-$($kv.Key)" }
        } else {
            $parts += "-$($kv.Key)"
            $parts += ('"{0}"' -f $kv.Value)
        }
    }
    $exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
    Write-Step 'Administrator rights required - relaunching elevated (accept the UAC prompt)...'
    Start-Process $exe -Verb RunAs -ArgumentList ($parts -join ' ')
}

# Stop the autostart task and kill any lingering PluginLoader processes so the
# exe files become unlocked for replacement.
function Stop-DeckyTask {
    if (Get-ScheduledTask -TaskName $script:DeckyTaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $script:DeckyTaskName -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
    Get-Process 'PluginLoader', 'PluginLoader_noconsole' -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch { }
    }
}

# Register the elevated, run-at-logon autostart task. Startup-folder shortcuts
# cannot elevate, so a scheduled task with highest privileges is the reliable path.
function Register-DeckyTask {
    param([Parameter(Mandatory)][string]$ExePath)
    $user      = "$env:USERDOMAIN\$env:USERNAME"
    $action    = New-ScheduledTaskAction    -Execute $ExePath -WorkingDirectory (Split-Path $ExePath -Parent)
    $trigger   = New-ScheduledTaskTrigger   -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal  -UserId $user -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $settings.ExecutionTimeLimit = 'PT0S'   # no time limit
    Register-ScheduledTask -TaskName $script:DeckyTaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
}

# Write a UTF-8 (no BOM) text file. Decky parses loader.json with Python json,
# which chokes on a BOM, so never use Set-Content -Encoding utf8 for it.
function Write-TextFileNoBom {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}
