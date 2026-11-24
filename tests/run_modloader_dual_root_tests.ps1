# run_modloader_dual_root_tests.ps1
#
# One-command launcher for ticket 029's ModLoader dual-root harness. Boots
# ModLoaderDualRootBootstrap.tscn headlessly and treats the runner's printed
# marker as authoritative (the Godot 4.2.1 console exe can exit non-zero under
# PowerShell even on a clean --quit run).

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
$logPath = Join-Path $env:TEMP 'renai-modloader-dual-root-029.log'
$errLogPath = Join-Path $env:TEMP 'renai-modloader-dual-root-029.err.log'

if (-not (Test-Path $GodotPath)) {
    Write-Host "Cannot find Godot at '$GodotPath'."
    Write-Host 'Pass -GodotPath <exe>, set GODOT_PATH, or add the console exe to PATH.'
    exit 1
}

Write-Host "Running ticket 029 ModLoader dual-root harness from $projectRoot"
& $GodotPath --headless --path $projectRoot 'res://tests/ModLoaderDualRootBootstrap.tscn' 2>$errLogPath | Tee-Object -FilePath $logPath
$godotExit = $LASTEXITCODE

$output = Get-Content -Path $logPath -Raw
Write-Host "Godot raw exit code: $godotExit"

if ($output -match 'ALL_029_CHECKS_PASSED' -and $output -notmatch '\[029\] FAIL') {
    Write-Host 'MODLOADER_DUAL_ROOT_029_OK'
    exit 0
}

if (Test-Path $errLogPath) {
    Write-Host '--- Godot stderr ---'
    Get-Content -Path $errLogPath
}
Write-Host 'MODLOADER_DUAL_ROOT_029_FAILED'
exit 1
