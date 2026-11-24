# run_chunk_tests_019.ps1
#
# One-command launcher for ticket 019's tiered-simulation harness. Boots
# ChunkManagerBootstrap.tscn headlessly; the runner's printed marker is the
# pass/fail signal (the Godot 4.2.1 console exe can exit non-zero under PowerShell
# even on a clean --quit run, as recorded in ticket 018).
#
# Godot lookup order: -GodotPath parameter, GODOT_PATH env var, PATH, then the
# documented local default (D:\Godot\Godot_v4.2.1-stable_win64_console.exe).

param([string]$GodotPath = $env:GODOT_PATH)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $found = Get-Command 'Godot_v4.2.1-stable_win64_console.exe' -ErrorAction SilentlyContinue
    if ($null -ne $found) {
        $GodotPath = $found.Source
    }
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = 'D:\Godot\Godot_v4.2.1-stable_win64_console.exe'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $env:TEMP 'renai-chunkmanager-019.log'

if (-not (Test-Path $GodotPath)) {
    Write-Host "Cannot find Godot at '$GodotPath'."
    Write-Host 'Pass -GodotPath <exe>, set GODOT_PATH, or add the console exe to PATH.'
    exit 1
}

Write-Host "Running ticket 019 ChunkManager harness from $projectRoot"
& $GodotPath --headless --path $projectRoot 'res://tests/ChunkManagerBootstrap.tscn' 2>&1 | Tee-Object -FilePath $logPath
$godotExit = $LASTEXITCODE

$output = Get-Content -Path $logPath -Raw
Write-Host "Godot raw exit code: $godotExit"

if ($output -match 'ALL_019_CHECKS_PASSED' -and $output -notmatch '\[019\] FAIL') {
    Write-Host 'CHUNKMANAGER_019_OK'
    exit 0
}

Write-Host 'CHUNKMANAGER_019_FAILED'
exit 1
