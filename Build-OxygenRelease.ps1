$ErrorActionPreference = "Stop"

$ProjectRoot = $PSScriptRoot
$Pubspec = Join-Path $ProjectRoot "pubspec.yaml"
$Flutter = Get-Command flutter -ErrorAction SilentlyContinue

if (-not (Test-Path $Pubspec)) {
    throw "pubspec.yaml was not found. Extract this script into the root of your Flutter project."
}
if (-not $Flutter) {
    throw "Flutter was not found in PATH. Open a terminal where 'flutter --version' works."
}

Set-Location $ProjectRoot
Write-Host "Getting Flutter packages..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }

Write-Host "Building Oxygen for Windows (Release)..." -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Flutter Windows Release build failed." }

$RunnerRelease = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$Exe = Join-Path $RunnerRelease "oxygen.exe"
if (-not (Test-Path $Exe)) {
    throw "oxygen.exe was not found at '$Exe'. Check the build output and your Windows runner target name."
}
if (-not (Test-Path (Join-Path $RunnerRelease "data"))) {
    throw "The Release data folder is missing. The build may not have completed successfully."
}

$DistRoot = Join-Path $ProjectRoot "dist"
$Portable = Join-Path $DistRoot "Oxygen-Portable"
New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null
if (Test-Path $Portable) { Remove-Item -Recurse -Force $Portable }
New-Item -ItemType Directory -Force -Path $Portable | Out-Null
Copy-Item -Path (Join-Path $RunnerRelease "*") -Destination $Portable -Recurse -Force

$ZipPath = Join-Path $DistRoot "Oxygen-Portable-Windows-x64.zip"
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Compress-Archive -Path (Join-Path $Portable "*") -DestinationPath $ZipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "Build completed." -ForegroundColor Green
Write-Host "Portable folder: $Portable"
Write-Host "Portable ZIP:    $ZipPath"
Write-Host "Run oxygen.exe from the portable folder; keep its data and DLL files beside it."
Write-Host "To create Setup.exe or MSI, install Inno Setup or WiX and run Build-Installers.ps1."
