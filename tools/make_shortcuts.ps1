# Puts Gemhalla shortcuts with their own icons on the desktop:
#   "Gemhalla"        the game (Rune Gem icon); asks for the player's name
#   "Gemhalla - <n>"  with -Session <n>: straight into that player's session
#   "Gemhalla Admin"  the admin page (sapphire icon)
# A link dragged from the browser shows the browser's icon; these show Gemhalla's.
# The icons are copied to %LOCALAPPDATA%\Gemhalla\icons, so the shortcuts keep them
# even if this folder moves. Use -Url for a Gemhalla server somewhere else,
# and -Name to choose the game shortcut's name (replacing a shortcut of that name).
param(
    [string]$Session = "",
    [string]$Name = "",
    [string]$Url = "http://localhost:8070",
    [switch]$NoAdmin
)

$project = Split-Path -Parent $PSScriptRoot
$iconDir = Join-Path $env:LOCALAPPDATA "Gemhalla\icons"
New-Item -ItemType Directory -Force $iconDir | Out-Null
Copy-Item (Join-Path $project "assets\icons\gemhalla.ico") $iconDir -Force
Copy-Item (Join-Path $project "assets\icons\admin.ico") $iconDir -Force

$desktop = [Environment]::GetFolderPath("Desktop")
$base = $Url.TrimEnd("/")

function New-Shortcut([string]$name, [string]$target, [string]$icon) {
    $path = Join-Path $desktop "$name.url"
    $lines = @(
        "[InternetShortcut]",
        "URL=$target",
        "IconFile=$(Join-Path $iconDir $icon)",
        "IconIndex=0"
    )
    Set-Content -Path $path -Value $lines -Encoding ascii
    Write-Host "Made $path -> $target"
}

if ($Session) {
    if (-not $Name) { $Name = "Gemhalla - $Session" }
    New-Shortcut $Name "$base/?session=$([Uri]::EscapeDataString($Session))" "gemhalla.ico"
} else {
    if (-not $Name) { $Name = "Gemhalla" }
    New-Shortcut $Name "$base/" "gemhalla.ico"
}
if (-not $NoAdmin) {
    New-Shortcut "Gemhalla Admin" "$base/admin" "admin.ico"
}
