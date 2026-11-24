# run_main_menu_tests.ps1
#
# One-command launcher for ticket 026's main-menu acceptance harness. Boots the
# real GameManager routes headlessly through MainMenuBootstrap.tscn and treats
# the runner's printed marker as authoritative: the Godot 4.2.1 console exe can
# exit non-zero under PowerShell even on a clean --quit run, so its raw exit
# code is logged but not used as the pass/fail signal.
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
$logPath = Join-Path $env:TEMP 'renai-main-menu-026.log'

if (-not (Test-Path $GodotPath)) {
    Write-Host "Cannot find Godot at '$GodotPath'."
    Write-Host 'Pass -GodotPath <exe>, set GODOT_PATH, or add the console exe to PATH.'
    exit 1
}

Write-Host "Running ticket 026 main-menu harness from $projectRoot"
& $GodotPath --headless --path $projectRoot 'res://tests/MainMenuBootstrap.tscn' 2>&1 | Tee-Object -FilePath $logPath
$godotExit = $LASTEXITCODE

$output = Get-Content -Path $logPath -Raw
Write-Host "Godot raw exit code: $godotExit"

if ($output -match 'ALL_026_CHECKS_PASSED' -and $output -notmatch '\[026\] FAIL') {
    Write-Host 'MAIN_MENU_026_OK'
    exit 0
}

Write-Host 'MAIN_MENU_026_FAILED'
exit 1
