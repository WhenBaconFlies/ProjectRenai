# run_settings_manager_tests.ps1
#
# One-command launcher for ticket 025's SettingsManager harness. Boots
# SettingsManagerBootstrap.tscn headlessly and treats the runner's printed
# marker as authoritative (the Godot 4.2.1 console exe can exit non-zero under
# PowerShell even on a clean --quit run).
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
$logPath = Join-Path $env:TEMP 'renai-settings-manager-025.log'
$errLogPath = Join-Path $env:TEMP 'renai-settings-manager-025.err.log'

if (-not (Test-Path $GodotPath)) {
    Write-Host "Cannot find Godot at '$GodotPath'."
    Write-Host 'Pass -GodotPath <exe>, set GODOT_PATH, or add the console exe to PATH.'
    exit 1
}

Write-Host "Running ticket 025 SettingsManager harness from $projectRoot"
# T15 deliberately writes a malformed ConfigFile, so Godot emits a parse error
# to stderr on a passing run. Capture it beside stdout instead of rendering it
# as a PowerShell NativeCommandError; show it only when the run actually fails.
& $GodotPath --headless --path $projectRoot 'res://tests/SettingsManagerBootstrap.tscn' 2>$errLogPath | Tee-Object -FilePath $logPath
$godotExit = $LASTEXITCODE

$output = Get-Content -Path $logPath -Raw
Write-Host "Godot raw exit code: $godotExit"

if ($output -match 'ALL_025_CHECKS_PASSED' -and $output -notmatch '\[025\] FAIL') {
    Write-Host 'SETTINGS_MANAGER_025_OK'
    exit 0
}

if (Test-Path $errLogPath) {
    Write-Host '--- Godot stderr ---'
    Get-Content -Path $errLogPath
}
Write-Host 'SETTINGS_MANAGER_025_FAILED'
exit 1
