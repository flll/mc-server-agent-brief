#Requires -Version 5.1
$ErrorActionPreference = "Stop"

Set-Location (Split-Path -Parent $PSScriptRoot)

if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^\s*([^#=]+?)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-Item -Path "env:$name" -Value $value
        }
    }
}

if (-not $env:SERVER_NAME) {
    Write-Error "SERVER_NAME is not set in .env"
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
New-Item -ItemType Directory -Force -Path "backups" | Out-Null

Write-Host "Flushing world data..."
docker compose exec -T mc rcon-cli save-all flush 2>$null

Write-Host "Stopping server for consistent backup..."
docker compose stop mc

$archive = "backups\$($env:SERVER_NAME)_data_$ts.tar.gz"
tar -czf $archive -C . data

Write-Host "Starting server..."
docker compose start mc

Write-Host "Backup complete: $archive"
