$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "output"
New-Item -ItemType Directory -Force -Path $out | Out-Null
Start-Process explorer.exe -ArgumentList (Resolve-Path $out).Path
Write-Host "Ausgabeordner: $out"
Write-Host "IPA-Dateien entstehen auf einem Mac oder über GitHub Actions mit Signing-Zertifikat."
