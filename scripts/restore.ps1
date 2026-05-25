#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$Restore
)

$ErrorActionPreference = "Stop"

Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path $Restore)) {
    Write-Error "Backup file not found: $Restore"
}

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

Write-Host "Stopping containers..."
docker compose down

if (Test-Path "data") {
    $old = "data.old.$(Get-Date -UFormat %s)"
    Write-Host "Moving existing data/ to $old/"
    Move-Item -Path "data" -Destination $old
}

Write-Host "Extracting $Restore..."
tar -xzf $Restore

Write-Host "Restore complete. Run 'make up' or 'docker compose up -d' to start the server."
