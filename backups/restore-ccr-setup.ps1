<#
.SYNOPSIS
    Automated restoration script for CCR and Claude Code Setup Configuration
.DESCRIPTION
    Restores the backed-up configurations (settings.json, config.json, ccr-route-matrix.json, and ccr.ps1) 
    back to their respective global environment folders.
#>

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$claudeSettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$ccrConfigDir = Join-Path $env:USERPROFILE ".claude-code-router"
$ccrConfigPath = Join-Path $ccrConfigDir "config.json"
$ccrMatrixPath = Join-Path $ccrConfigDir "ccr-route-matrix.json"
$npmBinPath = Join-Path $env:APPDATA "npm\ccr.ps1"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " CCR and Claude Code Setup Restoration Tool " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will overwrite your current global Claude and CCR settings." -ForegroundColor Yellow
$confirm = Read-Host "Are you sure you want to restore the CCR environment? (Y/N)"

if ($confirm -notmatch "^[Yy]$") {
    Write-Host "Restoration cancelled." -ForegroundColor Red
    exit
}

Write-Host "`n[1/4] Restoring ~/.claude/settings.json..."
if (-not (Test-Path (Split-Path $claudeSettingsPath -Parent))) { New-Item -ItemType Directory -Force -Path (Split-Path $claudeSettingsPath -Parent) | Out-Null }
Copy-Item -Path (Join-Path $scriptDir "settings.json") -Destination $claudeSettingsPath -Force

Write-Host "[2/4] Restoring ~/.claude-code-router/config.json..."
if (-not (Test-Path $ccrConfigDir)) { New-Item -ItemType Directory -Force -Path $ccrConfigDir | Out-Null }
Copy-Item -Path (Join-Path $scriptDir "config.json") -Destination $ccrConfigPath -Force

Write-Host "[3/4] Restoring ~/.claude-code-router/ccr-route-matrix.json..."
Copy-Item -Path (Join-Path $scriptDir "ccr-route-matrix.json") -Destination $ccrMatrixPath -Force

Write-Host "[4/4] Restoring %APPDATA%/npm/ccr.ps1..."
if (-not (Test-Path (Split-Path $npmBinPath -Parent))) { New-Item -ItemType Directory -Force -Path (Split-Path $npmBinPath -Parent) | Out-Null }
Copy-Item -Path (Join-Path $scriptDir "ccr.ps1") -Destination $npmBinPath -Force

Write-Host "`nDone! CCR and Claude Code Setup has been perfectly restored." -ForegroundColor Green
Write-Host "Please run 'ccr restart' to ensure the router reloads the config." -ForegroundColor Cyan
