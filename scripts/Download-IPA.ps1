$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "output"
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "Lade neueste IPA von GitHub Actions..."
gh run list --repo NOCO-OS-DEVELOPER-TEAM/NOCO-RUNNING --workflow "Build IPA" --limit 5

$run = gh run list --repo NOCO-OS-DEVELOPER-TEAM/NOCO-RUNNING --workflow "Build IPA" --json databaseId,status,conclusion,displayTitle,headSha --limit 20 |
    ConvertFrom-Json |
    Where-Object { $_.status -eq "completed" -and $_.conclusion -eq "success" } |
    Select-Object -First 1

if (-not $run) {
    Write-Host "Noch kein erfolgreicher IPA-Build. Ich starte einen."
    gh workflow run "Build IPA" --repo NOCO-OS-DEVELOPER-TEAM/NOCO-RUNNING
    Write-Host "Warte auf den Lauf..."
    Start-Sleep -Seconds 8
    $pending = gh run list --repo NOCO-OS-DEVELOPER-TEAM/NOCO-RUNNING --workflow "Build IPA" --json databaseId,status --limit 1 | ConvertFrom-Json
    if ($pending) {
        gh run watch $pending[0].databaseId --repo NOCO-OS-DEVELOPER-TEAM/NOCO-RUNNING
        $run = gh run list --repo NOCO-OS-DEVELOPER-TEAM/NOCO-RUNNING --workflow "Build IPA" --json databaseId,status,conclusion --limit 5 |
            ConvertFrom-Json |
            Where-Object { $_.status -eq "completed" -and $_.conclusion -eq "success" } |
            Select-Object -First 1
    }
}

if (-not $run) {
    throw "IPA-Build ist noch nicht fertig oder fehlgeschlagen. GitHub Actions im Browser prüfen."
}

$stage = Join-Path $out "gh-ipa"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
gh run download $run.databaseId --repo NOCO-OS-DEVELOPER-TEAM/NOCO-RUNNING --name NOCORunning-ipa --dir $stage
Get-ChildItem $stage -Recurse -Filter *.ipa | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $out "NOCORunning.ipa") -Force
}
Start-Process explorer.exe -ArgumentList (Resolve-Path $out).Path
Write-Host "Fertig: $out\NOCORunning.ipa"
Write-Host "Sideloading z.B. mit Sideloadly (Apple-ID signiert die IPA auf dem Windows-PC)."
