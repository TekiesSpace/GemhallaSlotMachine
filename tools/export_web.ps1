# Exports the browser build to build/web and serves it at http://localhost:8060
# (use -NoServe to only export).
# Needs Godot's export templates (Editor > Manage Export Templates, or the .tpz from
# https://github.com/godotengine/godot-builds/releases) installed for this Godot version.
param(
    # Godot 4.7 (the console build on Windows): -Godot, else the GODOT environment variable, else godot on PATH.
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "godot" }),
    [switch]$NoServe
)

$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project "build\web"
New-Item -ItemType Directory -Force $out | Out-Null
& $Godot --headless --path $project --export-release "Web" (Join-Path $out "index.html")
if ($LASTEXITCODE -ne 0) { Write-Error "Export failed"; exit 1 }
# The build contains the Godot engine: ship its license and third-party notices with it.
Copy-Item (Join-Path $project "licenses\godot\LICENSE.txt") (Join-Path $out "GODOT-LICENSE.txt")
Copy-Item (Join-Path $project "licenses\godot\COPYRIGHT.txt") (Join-Path $out "GODOT-COPYRIGHT.txt")
Copy-Item (Join-Path $project "NOTICE.md") (Join-Path $out "NOTICE.md")
# Zip ready to upload to itch.io (or any static host).
$zip = Join-Path $project "build\gemhalla-web.zip"
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force
Write-Host "Upload-ready zip: $zip"
if (-not $NoServe) {
    & (Join-Path $PSScriptRoot "serve_web.ps1")
}
