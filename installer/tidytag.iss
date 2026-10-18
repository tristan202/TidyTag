; Inno Setup script for TidyTag. Built by tools\make-release.ps1, which passes the version:
;   ISCC.exe /DAppVersion=0.9.0 installer\tidytag.iss
; The installer can install for the current user (no administrator rights) or for everyone.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F1E9C2A-4B7D-4E59-9D3A-2C8B1F0E7A41}
AppName=TidyTag
AppVersion={#AppVersion}
AppVerName=TidyTag {#AppVersion}
AppPublisher=tristan202
AppPublisherURL=https://github.com/tristan202/TidyTag
AppSupportURL=https://github.com/tristan202/TidyTag/issues
AppUpdatesURL=https://github.com/tristan202/TidyTag/releases
DefaultDirName={autopf}\TidyTag
DefaultGroupName=TidyTag
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
SetupIconFile=..\TidyTag.ico
UninstallDisplayIcon={app}\TidyTag.exe
UninstallDisplayName=TidyTag {#AppVersion}
OutputDir=..\release
OutputBaseFilename=TidyTag-{#AppVersion}-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; per-user install by default; the user may choose "all users" (asks for administrator rights)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
VersionInfoVersion={#AppVersion}
VersionInfoProductName=TidyTag
VersionInfoDescription=TidyTag setup

[Languages]
Name: "danish"; MessagesFile: "compiler:Languages\Danish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "swedish"; MessagesFile: "compiler:Languages\Swedish.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\bin\TidyTag.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\languages\*.po"; DestDir: "{app}\languages"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
; language files of an older version that no longer exist
Type: files; Name: "{app}\languages\*.po"

[Icons]
Name: "{autoprograms}\TidyTag"; Filename: "{app}\TidyTag.exe"
Name: "{autodesktop}\TidyTag"; Filename: "{app}\TidyTag.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\TidyTag.exe"; Description: "{cm:LaunchProgram,TidyTag}"; Flags: nowait postinstall skipifsilent

; The settings in %LOCALAPPDATA%\TidyTag are left alone on uninstall, like most programs do.
