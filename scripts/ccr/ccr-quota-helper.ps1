[CmdletBinding()]
param(
  [int]$WindowHours = 24,
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Convert-FromUnixMilliseconds {
  param([long]$Milliseconds)

  return [DateTimeOffset]::FromUnixTimeMilliseconds($Milliseconds).LocalDateTime
}

function Get-StatusRank {
  param([string]$Status)

  switch ($Status) {
    "rate_limited_per_day" { return 7 }
    "privacy_policy_blocked" { return 6 }
    "model_access_error" { return 5 }
    "rate_limited_per_min" { return 4 }
    "upstream_rate_limited" { return 3 }
    "context_limited" { return 2 }
    "other_error" { return 1 }
    default { return 0 }
  }
}

function Get-ModelStatus {
  param(
    [string]$Message,
    [int]$HttpCode
  )

  $text = "$Message"

  if ($HttpCode -eq 429 -and $text -match "free-models-per-day") {
    return "rate_limited_per_day"
  }

  if ($HttpCode -eq 429 -and $text -match "free-models-per-min") {
    return "rate_limited_per_min"
  }

  if ($HttpCode -eq 429) {
    return "upstream_rate_limited"
  }

  if ($HttpCode -eq 404 -and $text -match "guardrail restrictions and data policy|settings/privacy|No endpoints available matching") {
    return "privacy_policy_blocked"
  }

  if ($HttpCode -eq 404 -and $text -match "may not exist|may not have access|invalid model|does not exist") {
    return "model_access_error"
  }

  if ($text -match "guardrail restrictions and data policy|settings/privacy|No endpoints available matching") {
    return "privacy_policy_blocked"
  }

  if ($text -match "may not exist|may not have access|invalid model|does not exist") {
    return "model_access_error"
  }

  if ($text -match "context length|too many tokens|max context|maximum context|prompt is too long") {
    return "context_limited"
  }

  return "other_error"
}

function Get-ModelEvents {
  param(
    [string]$LogDir,
    [datetime]$Since
  )

  $events = @{}
  $files = Get-ChildItem $LogDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $Since } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 20

  foreach ($file in $files) {
    foreach ($line in (Get-Content $file.FullName -ErrorAction SilentlyContinue)) {
      if ($line -notmatch "Error from provider\(") {
        continue
      }

      try {
        $row = $line | ConvertFrom-Json
      } catch {
        continue
      }

      $message = [string]$row.msg
      if (-not $message) {
        continue
      }

      if ($message -notmatch "Error from provider\((.+): (\d+)\):") {
        continue
      }

      $model = $Matches[1]
      $httpCode = [int]$Matches[2]
      $status = Get-ModelStatus -Message $message -HttpCode $httpCode
      $timestamp = $null
      if ($row.time) {
        $timestamp = Convert-FromUnixMilliseconds -Milliseconds ([long]$row.time)
      }

      $event = [pscustomobject]@{
        model = $model
        httpCode = $httpCode
        status = $status
        message = $message
        timestamp = $timestamp
        logFile = $file.FullName
      }

      if (-not $events.ContainsKey($model)) {
        $events[$model] = @()
      }

      $events[$model] += $event
    }
  }

  return $events
}

function Get-ModelHealth {
  param(
    [string]$Model,
    [hashtable]$Events
  )

  if (-not $Events.ContainsKey($Model) -or $Events[$Model].Count -eq 0) {
    return [pscustomobject]@{
      model = $Model
      status = "healthy"
      httpCode = $null
      timestamp = $null
      summary = "No recent provider errors in CCR logs."
    }
  }

  $ranked = $Events[$Model] |
    Sort-Object @{ Expression = { Get-StatusRank -Status $_.status }; Descending = $true }, @{ Expression = { $_.timestamp }; Descending = $true }

  $top = $ranked | Select-Object -First 1
  return [pscustomobject]@{
    model = $Model
    status = $top.status
    httpCode = $top.httpCode
    timestamp = $top.timestamp
    summary = $top.message
  }
}

function Get-FallbackRecommendation {
  param(
    [string]$Role,
    [string]$CurrentModel,
    [pscustomobject]$CurrentHealth,
    [hashtable]$RoleOrder,
    [hashtable]$Events
  )

  $preferred = @($RoleOrder[$Role])
  if (-not $preferred -or $preferred.Count -eq 0) {
    return $null
  }

  if ($CurrentHealth.status -eq "healthy") {
    return $null
  }

  foreach ($candidate in $preferred) {
    if ($candidate -eq $CurrentModel) {
      continue
    }

    $candidateHealth = Get-ModelHealth -Model $candidate -Events $Events
    if ($candidateHealth.status -eq "healthy") {
      return [pscustomobject]@{
        role = $Role
        currentModel = $CurrentModel
        currentStatus = $CurrentHealth.status
        recommendedModel = $candidate
        reason = "Current model is $($CurrentHealth.status); first healthy fallback in role order is $candidate."
      }
    }
  }

  return [pscustomobject]@{
    role = $Role
    currentModel = $CurrentModel
    currentStatus = $CurrentHealth.status
    recommendedModel = $null
    reason = "Current model is $($CurrentHealth.status); no healthy fallback found in role order."
  }
}

$ccrConfigPath = Join-Path $env:USERPROFILE ".claude-code-router\config.json"
$claudeSettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$logDir = Join-Path $env:USERPROFILE ".claude-code-router\logs"
$matrixPath = Join-Path $PSScriptRoot "ccr-route-matrix.json"
$since = (Get-Date).AddHours(-1 * $WindowHours)

if (-not (Test-Path $ccrConfigPath)) {
  throw "CCR config not found at $ccrConfigPath"
}

if (-not (Test-Path $matrixPath)) {
  throw "Route matrix not found at $matrixPath"
}

$ccrConfig = Get-Content $ccrConfigPath -Raw | ConvertFrom-Json
$claudeSettings = $null
if (Test-Path $claudeSettingsPath) {
  $claudeSettings = Get-Content $claudeSettingsPath -Raw | ConvertFrom-Json
}

$matrix = Get-Content $matrixPath -Raw | ConvertFrom-Json
$roleOrder = @{}
foreach ($property in $matrix.roles.PSObject.Properties) {
  $roleOrder[$property.Name] = @($property.Value)
}

$events = Get-ModelEvents -LogDir $logDir -Since $since
$roles = @("default", "background", "think", "longContext", "webSearch", "image", "code")
$routeRows = @()
$recommendations = @()

foreach ($role in $roles) {
  $currentModel = [string]$ccrConfig.Router.$role
  if (-not $currentModel) {
    continue
  }

  $health = Get-ModelHealth -Model $currentModel -Events $events
  $routeRows += [pscustomobject]@{
    role = $role
    model = $currentModel
    status = $health.status
    httpCode = $health.httpCode
    lastSeen = $health.timestamp
  }

  $fallback = Get-FallbackRecommendation -Role $role -CurrentModel $currentModel -CurrentHealth $health -RoleOrder $roleOrder -Events $events
  if ($fallback) {
    $recommendations += $fallback
  }
}

$eventSummary = @()
foreach ($key in ($events.Keys | Sort-Object)) {
  $health = Get-ModelHealth -Model $key -Events $events
  $eventSummary += [pscustomobject]@{
    model = $key
    status = $health.status
    httpCode = $health.httpCode
    lastSeen = $health.timestamp
  }
}

$report = [pscustomobject]@{
  generatedAt = Get-Date
  windowHours = $WindowHours
  claudeSelectedModel = if ($claudeSettings) { [string]$claudeSettings.model } else { $null }
  ccrDefaultModel = [string]$ccrConfig.Router.default
  routes = $routeRows
  recommendations = $recommendations
  recentErrors = $eventSummary
}

if ($AsJson) {
  $report | ConvertTo-Json -Depth 6
  exit 0
}

Write-Host "CCR quota helper"
Write-Host "Generated: $($report.generatedAt)"
Write-Host "Window:    last $WindowHours hour(s)"
Write-Host ""
Write-Host "Claude selected model: $($report.claudeSelectedModel)"
Write-Host "CCR default model:     $($report.ccrDefaultModel)"
if ($report.claudeSelectedModel -and $report.ccrDefaultModel -and $report.claudeSelectedModel -ne $report.ccrDefaultModel) {
  Write-Host "Note: Claude /model and CCR default are currently different."
}

Write-Host ""
Write-Host "Route health"
$report.routes | Format-Table -AutoSize role, model, status, httpCode, lastSeen | Out-Host

Write-Host ""
Write-Host "Recent error summary"
if ($report.recentErrors.Count -gt 0) {
  $report.recentErrors | Format-Table -AutoSize model, status, httpCode, lastSeen | Out-Host
} else {
  Write-Host "No recent CCR provider errors found."
}

Write-Host ""
Write-Host "Fallback recommendations"
if ($report.recommendations.Count -gt 0) {
  foreach ($item in $report.recommendations) {
    if ($item.recommendedModel) {
      Write-Host "- $($item.role): switch from $($item.currentModel) to $($item.recommendedModel)"
      Write-Host "  $($item.reason)"
    } else {
      Write-Host "- $($item.role): no healthy fallback found"
      Write-Host "  $($item.reason)"
    }
  }
} else {
  Write-Host "No route changes recommended from recent logs."
}
