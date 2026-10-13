OXYGEN WINDOWS DISTRIBUTION SCRIPTS

1. Extract these files into the root of your Flutter project, beside pubspec.yaml.
2. Open PowerShell in that folder.
3. If script execution is blocked, run:
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
4. Build a portable Release package:
   .\Build-OxygenRelease.ps1

The portable folder and ZIP are created under .\dist.
The portable package must keep oxygen.exe, data, and required DLL files together.

Optional Setup.exe:
- Install Inno Setup 6 from https://jrsoftware.org/isinfo.php
- Run .\Build-Installers.ps1

The script only builds an MSI if an installer\Oxygen.wxs file and WiX v4+ are available.
No prebuilt executable is included; build on the Windows machine with Flutter and Visual Studio C++ tools installed.
