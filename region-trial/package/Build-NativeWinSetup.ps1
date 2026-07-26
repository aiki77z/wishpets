param(
  [string]$OutputDir = ".\dist",
  [string]$Version = "1.0.1"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$packageDir = $PSScriptRoot
$outputRoot = Join-Path $repoRoot $OutputDir
$payloadDir = Join-Path $outputRoot "native-win-payload"
$payloadZip = Join-Path $outputRoot "native-win-payload.zip"
$assetStageDir = Join-Path $outputRoot "native-win-asset-stage"
$assetZip = Join-Path $outputRoot "wish-pets-assets.zip"
$assetPak = Join-Path $payloadDir "wish-pets-assets.pak"
$setupExe = Join-Path $outputRoot "WishPets-Setup-$Version.exe"
$launcherExe = Join-Path $payloadDir "WishPets.exe"
$iconPath = Join-Path $repoRoot "build\icon.ico"
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (-not (Test-Path -LiteralPath $csc)) {
  $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path -LiteralPath $csc)) {
  throw "C# compiler not found. Expected .NET Framework csc.exe."
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
if (Test-Path -LiteralPath $payloadDir) {
  Remove-Item -LiteralPath $payloadDir -Recurse -Force
}
if (Test-Path -LiteralPath $payloadZip) {
  Remove-Item -LiteralPath $payloadZip -Force
}
if (Test-Path -LiteralPath $assetStageDir) {
  Remove-Item -LiteralPath $assetStageDir -Recurse -Force
}
if (Test-Path -LiteralPath $assetZip) {
  Remove-Item -LiteralPath $assetZip -Force
}
if (Test-Path -LiteralPath $setupExe) {
  Remove-Item -LiteralPath $setupExe -Force
}
New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
New-Item -ItemType Directory -Path $assetStageDir -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $repoRoot "region-trial\Run-RegionPetTrial.ps1") -Destination $payloadDir
Copy-Item -LiteralPath (Join-Path $repoRoot "region-trial\README.md") -Destination $payloadDir
New-Item -ItemType Directory -Path (Join-Path $payloadDir "build") | Out-Null
Copy-Item -LiteralPath $iconPath -Destination (Join-Path $payloadDir "build\icon.ico")

$petSpritePaths = @(
  "jaehee\spritesheet.png",
  "kuri\spritesheet.png",
  "ryo\spritesheet.png",
  "sakupang\spritesheet.png",
  "sioning\spritesheet.png",
  "yushi\spritesheet.png"
)

foreach ($relative in $petSpritePaths) {
  $source = Join-Path $repoRoot $relative
  if (-not (Test-Path -LiteralPath $source)) {
    throw "Missing required sprite: $relative"
  }
  $destination = Join-Path $assetStageDir $relative
  New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
  Copy-Item -LiteralPath $source -Destination $destination
}

Compress-Archive -Path (Join-Path $assetStageDir "*") -DestinationPath $assetZip -Force
Move-Item -LiteralPath $assetZip -Destination $assetPak -Force
Remove-Item -LiteralPath $assetStageDir -Recurse -Force

& $csc /nologo /target:winexe /optimize+ /win32icon:$iconPath /out:$launcherExe /reference:System.Windows.Forms.dll (Join-Path $packageDir "WishPetsNativeLauncher.cs")
if ($LASTEXITCODE -ne 0) { throw "Launcher compilation failed." }

Compress-Archive -Path (Join-Path $payloadDir "*") -DestinationPath $payloadZip -Force

& $csc /nologo /target:winexe /optimize+ /win32icon:$iconPath /out:$setupExe /resource:$payloadZip,payload.zip /reference:System.Windows.Forms.dll /reference:System.IO.Compression.FileSystem.dll (Join-Path $packageDir "WishPetsNativeSetup.cs")
if ($LASTEXITCODE -ne 0) { throw "Setup compilation failed." }

Write-Host "Created $setupExe"
