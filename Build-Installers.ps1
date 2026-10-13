$ErrorActionPreference = "Stop"

$ProjectRoot = $PSScriptRoot
$Portable = Join-Path $ProjectRoot "dist\Oxygen-Portable"
$SetupScript = Join-Path $ProjectRoot "installer\Oxygen.iss"
$MsiProject = Join-Path $ProjectRoot "installer\Oxygen.wxs"

if (-not (Test-Path (Join-Path $Portable "oxygen.exe"))) {
    throw "Portable build not found. Run Build-OxygenRelease.ps1 first."
}

$Inno = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if (-not $Inno) {
    $Candidates = @(
        "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate) { $Inno = @{ Source = $Candidate }; break }
    }
}

if ($Inno -and (Test-Path $SetupScript)) {
    Write-Host "Building Setup.exe with Inno Setup..." -ForegroundColor Cyan
    & $Inno.Source $SetupScript
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed." }
} else {
    Write-Warning "Setup.exe skipped: Inno Setup 6 (ISCC.exe) or installer\Oxygen.iss was not found."
}

$Wix = Get-Command wix.exe -ErrorAction SilentlyContinue
if ($Wix -and (Test-Path $MsiProject)) {
    Write-Host "Building MSI with WiX..." -ForegroundColor Cyan
    $MsiOut = Join-Path $ProjectRoot "dist\Oxygen-x64.msi"
    & $Wix.Source build $MsiProject -o $MsiOut
    if ($LASTEXITCODE -ne 0) { throw "WiX MSI build failed." }
} else {
    Write-Warning "MSI skipped: WiX v4+ (wix.exe) or installer\Oxygen.wxs was not found."
}

Write-Host "Installer step finished. Check the dist folder." -ForegroundColor Green
