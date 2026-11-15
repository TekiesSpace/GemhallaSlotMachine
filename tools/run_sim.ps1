# Runs the headless RTP simulator. Example: .\tools\run_sim.ps1 -Spins 1000000 -Seed 42 -Lines 5
param(
    [int]$Spins = 200000,
    [int]$Seed = -1,
    [int]$Lines = 25,
    # Godot 4.7 (the console build on Windows): -Godot, else the GODOT environment variable, else godot on PATH.
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "godot" })
)

$project = Split-Path -Parent $PSScriptRoot
& $Godot --headless --path $project --script res://tools/rtp_sim.gd -- "--spins=$Spins" "--seed=$Seed" "--lines=$Lines"
