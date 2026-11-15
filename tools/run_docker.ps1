# Builds the Gemhalla Docker image and starts it with docker compose (local staging).
#   Game:  http://localhost:8070/?session=<name>
#   Admin: http://localhost:8070/admin
# Exports the game first if there's no browser build yet, or always with -Export.
# Stop it with: docker compose down   (sessions stay in the gemhalla-data volume)
param([switch]$Export)

$project = Split-Path -Parent $PSScriptRoot
if ($Export -or -not (Test-Path (Join-Path $project "build\web\index.html"))) {
    & (Join-Path $PSScriptRoot "export_web.ps1") -NoServe
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# The admin password lives in .env (git-ignored). Make a random one the first time.
$envFile = Join-Path $project ".env"
if (-not (Test-Path $envFile) -or -not (Select-String -Path $envFile -Pattern "^ADMIN_PASSWORD=." -Quiet)) {
    $alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789".ToCharArray()
    $bytes = New-Object byte[] 18
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    Add-Content -Path $envFile -Value "ADMIN_PASSWORD=$password" -Encoding ascii
    Write-Host "Made an admin password and saved it in .env:"
    Write-Host "  $password"
}

Push-Location $project
try {
    docker compose up --build -d
    if ($LASTEXITCODE -ne 0) { exit 1 }
    Write-Host ""
    Write-Host "Game:  http://localhost:8070/?session=alice   (use any name per session)"
    Write-Host "Admin: http://localhost:8070/admin   (password: ADMIN_PASSWORD in .env)"
    Write-Host "Logs:  docker compose logs -f     Stop: docker compose down"
} finally {
    Pop-Location
}
