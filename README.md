# decky-loader-windows

A self-maintained build & install pipeline for running **[Decky Loader](https://github.com/SteamDeckHomebrew/decky-loader) on Windows**, built straight from upstream source.

It exists because the Windows side of Decky is chronically under-distributed: upstream officially supports Windows in CI (`build-win.yml`) but **never attaches the Windows exes to releases**, and the community installers (e.g. `ACCESS-DENIIED/Decky-Loader-For-Windows`) go stale for months. When Steam updates its UI, old Decky builds crash (`findModuleByExport` → *"Cannot convert a Symbol value to a string"*) and the in-app updater **stalls on Windows** because there's no `PluginLoader.exe` release asset to download. This repo removes that dependency: you build the current loader yourself and install it in one command.

> This **fully replaces** the ACCESS-DENIIED installer. It does not use that repo at all — the actual loader code (and every Steam-compat fix) lives in upstream `decky-loader`, so we build from upstream directly.

## Install (for users)

Go to [**Releases**](https://github.com/Draek2077/decky-loader-windows/releases), download the latest **`decky-loader-<version>-setup.exe`** (e.g. `decky-loader-3.2.4-setup.exe`), and run it. The installer:

- deploys the loader to `%USERPROFILE%\homebrew\services`,
- creates the `homebrew` folder tree,
- enables Steam CEF remote debugging,
- registers the elevated run-at-logon autostart task.

Then fully restart Steam and open the Quick Access menu — the Decky icon appears. To update later, just run a newer installer from Releases.

## What it does (for maintainers)

- **`build.ps1`** — clones/pins upstream `decky-loader`, builds the React frontend + PyInstaller backend, outputs `PluginLoader.exe` and `PluginLoader_noconsole.exe` to `.\dist`. No admin needed.
- **`install.ps1`** — full install: creates `~/homebrew`, enables Steam CEF remote debugging, deploys the exes (with backup), and registers an **elevated run-at-logon scheduled task** (Startup-folder shortcuts can't elevate, which is why the icon silently failed to appear before). Self-elevates via UAC.
- **`update.ps1`** — resolves the latest upstream release, re-pins, rebuilds, and redeploys. This is your one-command recovery when a Steam update breaks Decky.
- **`uninstall.ps1`** — removes the autostart task (`-Purge` also wipes `~/homebrew` + the CEF flag).
- **`installer/decky-loader-windows.iss`** — Inno Setup script that packages the built exes + install logic into a single `setup.exe`.
- **`.github/workflows/build-release.yml`** — CI on `windows-2022` that builds the exes, compiles the installer, and **publishes `setup.exe` as a GitHub Release** (manual, on `upstream.ref`/`installer` change, and weekly). This is the distribution gap, fixed.

## Prerequisites (local builds)

- Git, **Python 3.10–3.13**, **Node 18+** with npm, and a working internet connection.
- `pnpm`, `poetry`, and `pyinstaller` are installed automatically (pnpm globally; poetry + pyinstaller into an isolated `.build\buildenv`).

## Quick start

```powershell
# from the repo root
.\install.ps1
# accept the UAC prompt, then fully restart Steam.
# Open the Quick Access menu (Big Picture) — the Decky icon should be there.
```

Build without installing:

```powershell
.\build.ps1            # uses upstream.ref
.\build.ps1 -Ref v3.2.4
```

## Updating / recovering after a Steam break

```powershell
.\update.ps1                  # -> latest upstream stable, rebuild, redeploy
.\update.ps1 -Prerelease      # newest upstream prerelease
.\update.ps1 -Ref v3.2.5-pre1 # a specific tag
```

`upstream.ref` records the pinned upstream version (currently **`v3.2.4`**). Bump it and re-run `install.ps1` (or push it to trigger CI) to move versions deliberately.

## How autostart works

A scheduled task named **`Decky Loader`** runs `PluginLoader_noconsole.exe` at logon with highest privileges (silent, no UAC at login). The legacy non-elevated Startup-folder shortcut, if found, is moved aside during install.

## Publishing (maintainer)

```powershell
git remote add origin https://github.com/Draek2077/decky-loader-windows.git
git push -u origin main
```

Then cut a release one of two ways:

- **Actions → Build & Release Windows Installer → Run workflow**, and type the **version** (e.g. `3.2.4`, or `3.2.5-pre1` for a prerelease — a leading `v` is optional). CI builds `decky-loader-<version>-setup.exe` and uploads it to a new Release. Prerelease tags (`-pre`/`-rc`) are auto-marked as prereleases.
- **Push a change to `upstream.ref`** to move the pinned default version; the same build+release runs automatically (also weekly).

## Troubleshooting

- **No icon after install** → fully quit and reopen Steam. Decky injects into Steam's UI on launch.
- **Confirm injection** → with Steam running, `Invoke-RestMethod http://localhost:8080/json` lists the CEF contexts; a healthy load exposes `window.DeckyPluginLoader` in `SharedJSContext`.
- **Port 1337 taken** → Decky's backend needs `127.0.0.1:1337`. Make sure nothing else (some RGB/peripheral services) is holding it.
- **In-app "update available" that stalls** → expected; Windows self-update is broken upstream. Use `update.ps1` instead.

## Licensing

Decky Loader is **GPLv2**; the binaries this repo builds are a GPLv2 work — corresponding source is the upstream `decky-loader` at the pinned `upstream.ref`. The wrapper scripts here are provided under the MIT License.

## Credits

All loader functionality is the work of the [SteamDeckHomebrew](https://github.com/SteamDeckHomebrew) team. This repo only builds and installs it for Windows.
