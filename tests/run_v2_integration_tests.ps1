# run_v2_integration_tests.ps1
#
# One-command launcher for ticket 033's v2 end-to-end harness. Boots the real
# menu/conversation/save/options/mods flow headlessly through
# V2IntegrationBootstrap.tscn and treats the runner's printed marker as
# authoritative: the Godot 4.2.1 console exe can exit non-zero under PowerShell
# even on a clean --quit run, so its raw exit code is not the pass/fail signal.
#
# Godot lookup order: -GodotPath parameter, GODOT_PATH env var, PATH, then the
# documented local default (D:\Godot\Godot_v4.2.1-stable_win64_console.exe).
# The fixed log is cleared first so a stale marker cannot fake a pass, and the
# run is bounded by a watchdog so a fatally aborted harness cannot hang the
# caller or leave its fixtures on disk unnoticed.

param([string]$GodotPath = $env:GODOT_PATH)

$ErrorActionPreference = 'Continue'
$TimeoutSeconds = 180

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
$logPath = Join-Path $env:TEMP 'renai-v2-integration-033.log'
Remove-Item -Path $logPath -ErrorAction SilentlyContinue

if (-not (Test-Path $GodotPath)) {
    Write-Host "Cannot find Godot at '$GodotPath'."
    Write-Host 'Pass -GodotPath <exe>, set GODOT_PATH, or add the console exe to PATH.'
    exit 1
}

Write-Host "Running ticket 033 v2 integration harness from $projectRoot (timeout $TimeoutSeconds s)"
$job = Start-Job -ScriptBlock {
    param($exe, $root)
    & $exe --headless --path $root 'res://tests/V2IntegrationBootstrap.tscn' 2>&1
} -ArgumentList $GodotPath, $projectRoot

$completed = Wait-Job $job -Timeout $TimeoutSeconds
if ($null -eq $completed) {
    Stop-Job $job -ErrorAction SilentlyContinue
    $partial = Receive-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($null -ne $partial) {
        $partial | Tee-Object -FilePath $logPath
    }
    Write-Host "V2_INTEGRATION_033_FAILED (timeout after $TimeoutSeconds s)"
    exit 1
}

$output = Receive-Job $job
Remove-Job $job
if ($null -ne $output) {
    $output | Tee-Object -FilePath $logPath
}

$text = Get-Content -Path $logPath -Raw
if ($text -match 'ALL_033_CHECKS_PASSED' -and $text -notmatch '\[033\] FAIL') {
    Write-Host 'V2_INTEGRATION_033_OK'
    exit 0
}

Write-Host 'V2_INTEGRATION_033_FAILED'
exit 1
