[CmdletBinding()]
param(
  [string]$Model,
  [string]$Prompt,
  [string[]]$CcrArgs = @(),
  [switch]$Preview,
  [string]$CcrCommand
)

$ErrorActionPreference = "Stop"

function Get-CcrCommand {
  param([string]$Override)

  if ($Override) {
    return $Override
  }

  $candidate = Join-Path $env:APPDATA "npm\ccr.cmd"
  if (Test-Path $candidate) {
    return $candidate
  }

  return "ccr"
}

function Set-ProcessEnv {
  param(
    [hashtable]$Values,
    [hashtable]$Previous
  )

  foreach ($entry in $Values.GetEnumerator()) {
    $name = [string]$entry.Key
    $Previous[$name] = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable($name, [string]$entry.Value, [EnvironmentVariableTarget]::Process)
  }
}

function Restore-ProcessEnv {
  param([hashtable]$Previous)

  foreach ($entry in $Previous.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable(
      [string]$entry.Key,
      [string]$entry.Value,
      [EnvironmentVariableTarget]::Process
    )
  }
}

$compatEnv = [ordered]@{
  CLAUDE_CODE_ATTRIBUTION_HEADER = "0"
  DISABLE_TELEMETRY = "1"
  DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1"
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
  CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = "1"
  CLAUDE_CODE_MAX_OUTPUT_TOKENS = "8192"
  DISABLE_COST_WARNINGS = "1"
}

if ($Model) {
  $compatEnv["ANTHROPIC_DEFAULT_OPUS_MODEL"]   = $Model
  $compatEnv["ANTHROPIC_DEFAULT_SONNET_MODEL"] = $Model
  $compatEnv["ANTHROPIC_DEFAULT_HAIKU_MODEL"]  = $Model
  $compatEnv["CLAUDE_CODE_SUBAGENT_MODEL"]     = $Model
}

$argsToPass = @("code")
if ($Model) {
  $argsToPass += @("--model", $Model)
}
if ($Prompt) {
  $argsToPass += @("-p", $Prompt)
}
if ($CcrArgs.Count -gt 0) {
  $argsToPass += $CcrArgs
}

$ccrCmd = Get-CcrCommand -Override $CcrCommand

if ($Preview) {
  Write-Host "CCR launch preview"
  Write-Host ("Command : {0}" -f $ccrCmd)
  Write-Host ("Args     : {0}" -f ($argsToPass -join " "))
  Write-Host ""
  Write-Host "Scoped env vars:"
  foreach ($entry in $compatEnv.GetEnumerator()) {
    Write-Host ("  {0}={1}" -f $entry.Key, $entry.Value)
  }
  exit 0
}

$previousEnv = @{}
Set-ProcessEnv -Values $compatEnv -Previous $previousEnv

try {
  & $ccrCmd @argsToPass
  exit $LASTEXITCODE
} finally {
  Restore-ProcessEnv -Previous $previousEnv
}
