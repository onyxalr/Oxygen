$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Test-Path (Join-Path $ProjectRoot 'pubspec.yaml'))) {
    throw 'pubspec.yaml was not found. Extract this package into your existing Flutter project root.'
}
if (-not (Test-Path (Join-Path $ProjectRoot 'android\gradlew.bat'))) {
    throw 'Android platform files are missing. Run flutter create . from the Flutter project root, then try again.'
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found in PATH. First make sure flutter --version works.'
}

Write-Host 'Resolving dependencies...' -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

Write-Host 'Building Oxygen APK (Release)...' -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'Android Release build failed. Check Android SDK, licenses and Gradle output above.' }

$BuiltApk = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $BuiltApk)) { throw "Expected APK was not found: $BuiltApk" }
$Dist = Join-Path $ProjectRoot 'dist'
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
$Destination = Join-Path $Dist 'Oxygen-Android-universal-release.apk'
Copy-Item $BuiltApk $Destination -Force
Write-Host ''
Write-Host 'Release APK created:' -ForegroundColor Green
Write-Host $Destination -ForegroundColor Green
