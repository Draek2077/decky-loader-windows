; Inno Setup script for decky-loader-windows.
; Produces a single setup.exe that bundles the built PluginLoader exes plus our
; install logic, and runs the full install (homebrew tree, Steam CEF flag,
; elevated autostart task) on the user's machine.
;
; Build:  ISCC.exe /DMyAppVersion=v3.2.4 installer\decky-loader-windows.iss
; Output: installer\Output\decky-loader-windows-setup-<ver>.exe

#ifndef MyAppVersion
  #define MyAppVersion "dev"
#endif

[Setup]
AppId={{B6D3D9C2-1E4A-4F2E-9C7E-DECKYWIN0001}
AppName=Decky Loader (Windows)
AppVersion={#MyAppVersion}
AppPublisher=Draek2077
AppPublisherURL=https://github.com/Draek2077/decky-loader-windows
DefaultDirName={autopf}\decky-loader-windows
DisableProgramGroupPage=yes
DisableDirPage=yes
; Sources below are relative to the repo root (parent of this script's folder).
SourceDir={#SourcePath}\..
OutputDir=installer\Output
OutputBaseFilename=decky-loader-{#MyAppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=Decky Loader (Windows)
InfoAfterFile=installer\post-install.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "dist\PluginLoader.exe";            DestDir: "{app}\dist"; Flags: ignoreversion
Source: "dist\PluginLoader_noconsole.exe";  DestDir: "{app}\dist"; Flags: ignoreversion
Source: "install.ps1";                       DestDir: "{app}";      Flags: ignoreversion
Source: "uninstall.ps1";                     DestDir: "{app}";      Flags: ignoreversion
Source: "lib\common.ps1";                    DestDir: "{app}\lib";  Flags: ignoreversion
Source: "README.md";                         DestDir: "{app}";      Flags: ignoreversion

; Run our deploy step. The installer is already elevated, so install.ps1 (-NoBuild)
; runs without a second UAC prompt and does the homebrew/CEF/autostart setup.
[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install.ps1"" -NoBuild"; \
  StatusMsg: "Installing Decky Loader (homebrew folder, Steam CEF, autostart task)..."; \
  Flags: runhidden waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"""; \
  Flags: runhidden waituntilterminated; RunOnceId: "DeckyUninstall"
