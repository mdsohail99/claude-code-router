#!/usr/bin/env pwsh
$basedir=Split-Path $MyInvocation.MyCommand.Definition -Parent

$exe=""
if ($PSVersionTable.PSVersion -lt "6.0" -or $IsWindows) {
  $exe=".exe"
}
$ret=0

function Get-CcrPort {
  $configPath = Join-Path $HOME ".claude-code-router\\config.json"
  if (Test-Path $configPath) {
    try {
      $config = Get-Content $configPath -Raw | ConvertFrom-Json
      if ($null -ne $config.PORT -and "$($config.PORT)" -match '^\d+$') {
        return [int]$config.PORT
      }
    } catch {
    }
  }

  return 3456
}

function Get-CcrListeningPid {
  param([int]$Port)

  try {
    $entries = netstat -ano -p tcp 2>$null | Select-String "LISTENING"
    foreach ($entry in $entries) {
      if ($entry.Line -match "^\s*TCP\s+\S+:$Port\s+\S+\s+LISTENING\s+(\d+)\s*$") {
        return [int]$Matches[1]
      }
    }
  } catch {
  }

  return $null
}

function Test-CcrProcess {
  param([int]$ProcessId)

  try {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId"
    return $null -ne $proc -and $proc.CommandLine -like "*claude-code-router*"
  } catch {
    return $false
  }
}

function Repair-CcrPidFile {
  try {
    $homeDir = Join-Path $HOME ".claude-code-router"
    $pidFile = Join-Path $homeDir ".claude-code-router.pid"
    $port = Get-CcrPort
    $listeningPid = Get-CcrListeningPid -Port $port

    if ($listeningPid -and (Test-CcrProcess -ProcessId $listeningPid)) {
      $currentPid = $null
      if (Test-Path $pidFile) {
        try {
          $currentPid = [int](Get-Content $pidFile -Raw).Trim()
        } catch {
        }
      }

      if ($currentPid -ne $listeningPid) {
        New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
        Set-Content -Path $pidFile -Value $listeningPid -NoNewline
      }
      return
    }

    if (Test-Path $pidFile) {
      Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
  } catch {
  }
}

Repair-CcrPidFile

if ($args.Count -gt 0 -and $args[0] -eq "--ccr-repair-only") {
  exit 0
}

# Resolve the CLI entry point dynamically:
# 1. Check if this is a local dev checkout (sibling packages/cli/dist/cli.js)
# 2. Fall back to the npm-installed path (relative to $basedir)
$devPath = "C:\Dev\claude-code-router\packages\cli\dist\cli.js"
$npmPath = Join-Path (Split-Path $basedir -Parent) "claude-code-router\packages\cli\dist\cli.js"
$npmRelPath = Join-Path $basedir "..\@CCR\cli\dist\cli.js"

if (Test-Path $devPath) {
  $cliPath = $devPath
} elseif (Test-Path $npmPath) {
  $cliPath = $npmPath
} elseif (Test-Path $npmRelPath) {
  $cliPath = $npmRelPath
} else {
  Write-Error "Cannot find cli.js. Tried: $devPath, $npmPath, $npmRelPath"
  exit 1
}

if (Test-Path "$basedir/node$exe") {
  if ($MyInvocation.ExpectingInput) {
    $input | & "$basedir/node$exe" $cliPath $args
  } else {
    & "$basedir/node$exe" $cliPath $args
  }
  $ret=$LASTEXITCODE
} else {
  if ($MyInvocation.ExpectingInput) {
    $input | & "node$exe" $cliPath $args
  } else {
    & "node$exe" $cliPath $args
  }
  $ret=$LASTEXITCODE
}
exit $ret
