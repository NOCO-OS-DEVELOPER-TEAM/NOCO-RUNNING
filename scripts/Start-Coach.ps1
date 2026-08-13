$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\server")
if (-not (Test-Path ".\.venv")) {
    python -m venv .venv
}
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt
$hostName = if ($env:NOCO_HOST) { $env:NOCO_HOST } else { "0.0.0.0" }
$port = if ($env:NOCO_PORT) { $env:NOCO_PORT } else { "8787" }
Write-Host "NOCO RUNNING Coach: http://${hostName}:${port}/health"
& .\.venv\Scripts\python.exe -m uvicorn app:app --host $hostName --port $port
