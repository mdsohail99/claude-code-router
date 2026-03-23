param(
  [Parameter(Mandatory = $true)]
  [string]$Model,

  [string]$Prompt = "Reply with exactly: ok",

  [int]$TailLines = 120
)

$ErrorActionPreference = "Continue"

$configPath = Join-Path $env:USERPROFILE ".claude-code-router\config.json"
$logDir = Join-Path $env:USERPROFILE ".claude-code-router\logs"
$ccrCmd = Join-Path $env:APPDATA "npm\ccr.cmd"
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "CCR diagnose started at $stamp"
Write-Host "Config: $configPath"
Write-Host "Model:  $Model"
Write-Host ""

$beforeLatest = Get-ChildItem $logDir -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (!(Test-Path $ccrCmd)) {
  $ccrCmd = "ccr"
}

Write-Host "Restarting CCR..."
& $ccrCmd restart 2>&1 | Out-Host

Write-Host ""
Write-Host "Running: ccr code --model `"$Model`" -p `"$Prompt`""
Write-Host ""

$output = & $ccrCmd code --model $Model -p $Prompt 2>&1
$exitCode = $LASTEXITCODE

Write-Host "=== Command Output ==="
if ($output) {
  $output | Out-Host
} else {
  Write-Host "<no output>"
}

Write-Host ""
Write-Host "ExitCode: $exitCode"

$afterLatest = Get-ChildItem $logDir -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if ($afterLatest) {
  Write-Host ""
  Write-Host "LatestLog: $($afterLatest.FullName)"
  Write-Host "LastWrite: $($afterLatest.LastWriteTime)"
  Write-Host ""
  Write-Host "=== Log Tail ==="
  Get-Content $afterLatest.FullName -Tail $TailLines
} else {
  Write-Host ""
  Write-Host "No CCR log file found in $logDir"
}

exit $exitCode
