# Runs the Gemhalla server: the browser game plus the admin page, on this PC only.
#   Game:  http://localhost:8070/?session=<name>   (each name is its own session)
#   Admin: http://localhost:8070/admin
# Exports the game first if there's no browser build yet, or always with -Export.
param([switch]$Export)

$project = Split-Path -Parent $PSScriptRoot
if ($Export -or -not (Test-Path (Join-Path $project "build\web\index.html"))) {
    & (Join-Path $PSScriptRoot "export_web.ps1") -NoServe
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$env:DOTNET_NOLOGO = "1"
Write-Host ""
Write-Host "Game:  http://localhost:8070/?session=alice   (use any name per session)"
Write-Host "Admin: http://localhost:8070/admin"
Write-Host "Ctrl+C to stop."
dotnet run --project (Join-Path $project "server") --no-launch-profile
