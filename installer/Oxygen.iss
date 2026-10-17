; Inno Setup script for Oxygen. Requires Inno Setup 6.
#define MyAppName "Oxygen"
#define MyAppVersion "3.5.1"
#define MyAppPublisher "Oxygen"
#define SourceDir "..\dist\Oxygen-Portable"

[Setup]
AppId={{8D3C2C4D-5C25-4C76-9D8A-7E5E7F00A351}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Oxygen
DefaultGroupName=Oxygen
OutputDir=..\dist
OutputBaseFilename=Oxygen-Setup-3.5.1
ArchitecturesInstallIn64BitMode=x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\oxygen.exe

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Oxygen"; Filename: "{app}\oxygen.exe"
Name: "{autodesktop}\Oxygen"; Filename: "{app}\oxygen.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\oxygen.exe"; Description: "Launch Oxygen"; Flags: postinstall nowait skipifsilent
