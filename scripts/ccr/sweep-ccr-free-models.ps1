[CmdletBinding()]
param(
  [string]$OutputJson = "c:\Dev\HeliSync\artifacts\ccr-free-model-sweep.json",
  [string]$OutputTable = "c:\Dev\HeliSync\artifacts\ccr-free-model-sweep.txt",
  [int]$RequestTimeoutSeconds = 180,
  [string]$SingleModel
)

$ErrorActionPreference = "Stop"

function Ensure-Directory {
  param([string]$Path)

  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
}

function Get-FreeModelIds {
  $response = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/models" -TimeoutSec 120
  return $response.data |
    Where-Object { $_.id -match ":free$" -or $_.id -eq "openrouter/auto" } |
    Select-Object -ExpandProperty id |
    Sort-Object -Unique
}

function Classify-Result {
  param(
    [int]$ExitCode,
    [string]$Output
  )

  $safeOutput = ""
  if ($null -ne $Output) {
    $safeOutput = [string]$Output
  }

  $normalized = $safeOutput.ToLowerInvariant()

  if ($ExitCode -eq 0 -and $normalized -match "(^|\r?\n)ok(\r?\n|$)") {
    return "working"
  }

  if ($normalized -match "429|rate.?limit|temporarily rate-limited") {
    return "rate_limited"
  }

  if ($normalized -match "guardrail restrictions and data policy|settings/privacy|no endpoints available matching") {
    return "privacy_policy_blocked"
  }

  if ($normalized -match "context length|too many tokens|max context|maximum context|prompt is too long") {
    return "context_limit"
  }

  if ($normalized -match "selected model.*may not exist|may not have access|invalid model|model.*does not exist") {
    return "model_access_error"
  }

  if ($normalized -match "service startup timeout|service not running") {
    return "service_issue"
  }

  if ($ExitCode -eq 0) {
    return "working_with_unexpected_output"
  }

  return "failed_other"
}

function Invoke-ModelSmokeTest {
  param(
    [string]$Model,
    [int]$TimeoutSeconds
  )

  $ccrCmd = Join-Path $env:APPDATA "npm\ccr.cmd"
  if (-not (Test-Path $ccrCmd)) {
    $ccrCmd = "ccr"
  }

  $arguments = @(
    "code",
    "--model",
    $Model,
    "-p",
    "Reply with exactly: ok"
  )

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $stdoutFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ccr-sweep-" + [guid]::NewGuid().ToString("N") + ".stdout.txt")
  $stderrFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ccr-sweep-" + [guid]::NewGuid().ToString("N") + ".stderr.txt")

  try {
    $process = Start-Process -FilePath $ccrCmd -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    $exitCode = $process.ExitCode
  } catch {
    $exitCode = 1
    Set-Content -Path $stderrFile -Value $_.ToString()
  } finally {
    $stopwatch.Stop()
  }

  $capturedLines = @()
  if (Test-Path $stdoutFile) {
    $stdout = (Get-Content $stdoutFile -Raw).Trim()
    if ($stdout) {
      $capturedLines += $stdout
    }
    Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue
  }

  if (Test-Path $stderrFile) {
    $stderr = (Get-Content $stderrFile -Raw).Trim()
    if ($stderr) {
      $capturedLines += $stderr
    }
    Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
  }

  $output = ($capturedLines -join [Environment]::NewLine).Trim()
  $status = Classify-Result -ExitCode $exitCode -Output $output

  return [pscustomobject]@{
    model = $Model
    exitCode = $exitCode
    status = $status
    durationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    output = $output
  }
}

function Invoke-CcrFreeModelSweep {
  param(
    [string]$JsonPath,
    [string]$TablePath,
    [int]$TimeoutSeconds,
    [string]$Model
  )

  Ensure-Directory -Path $JsonPath
  Ensure-Directory -Path $TablePath

  $null = ccr status
  if ($Model) {
    $testModels = @($Model)
  } else {
    $rawModelIds = Get-FreeModelIds
    $testModels = $rawModelIds | ForEach-Object { "openrouter,$_"}
  }

  $results = @()
  foreach ($currentModel in $testModels) {
    Write-Host "Testing $currentModel ..."
    $results += Invoke-ModelSmokeTest -Model $currentModel -TimeoutSeconds $TimeoutSeconds
  }

  $summary = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    totalModels = $results.Count
    statusCounts = $results | Group-Object status | Sort-Object Name | ForEach-Object {
      [pscustomobject]@{
        status = $_.Name
        count = $_.Count
      }
    }
    results = $results
  }

  $summary | ConvertTo-Json -Depth 6 | Set-Content -Path $JsonPath

  $table = $results |
    Sort-Object status, model |
    Format-Table -AutoSize model, status, exitCode, durationSeconds |
    Out-String

  $table | Set-Content -Path $TablePath
  return $results
}

if ($MyInvocation.InvocationName -ne '.') {
  $results = Invoke-CcrFreeModelSweep -JsonPath $OutputJson -TablePath $OutputTable -TimeoutSeconds $RequestTimeoutSeconds -Model $SingleModel
  $results |
    Sort-Object status, model |
    Format-Table -AutoSize model, status, exitCode, durationSeconds |
    Out-String
}
