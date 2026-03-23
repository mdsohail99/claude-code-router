[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$ConfigPath,
  [string]$MatrixPath,
  [string]$LogDir,
  [int]$WindowHours = 24,
  [string[]]$Roles = @("default", "background", "think", "longContext", "webSearch", "image", "code"),
  [switch]$Apply,
  [switch]$AllowOpenRouterAuto,
  [switch]$AsJson,
  [string]$BackupDir
)

$ErrorActionPreference = "Stop"
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

if (-not $ConfigPath) {
  $ConfigPath = Join-Path $env:USERPROFILE ".claude-code-router\config.json"
}

if (-not $MatrixPath) {
  $MatrixPath = Join-Path $scriptRoot "ccr-route-matrix.json"
}

if (-not $LogDir) {
  $LogDir = Join-Path $env:USERPROFILE ".claude-code-router\logs"
}

if (-not $BackupDir) {
  $BackupDir = Join-Path $env:USERPROFILE ".claude-code-router\backups"
}

function Convert-FromUnixMilliseconds {
  param([long]$Milliseconds)

  return [DateTimeOffset]::FromUnixTimeMilliseconds($Milliseconds).LocalDateTime
}

function Get-StatusRank {
  param([string]$Status)

  switch ($Status) {
    "rate_limited_per_day" { return 8 }
    "rate_limited_per_min" { return 7 }
    "privacy_policy_blocked" { return 6 }
    "model_access_error" { return 5 }
    "upstream_rate_limited" { return 4 }
    "context_limited" { return 3 }
    "other_error" { return 2 }
    default { return 1 }
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

  if ($text -match "context length|too many tokens|max context|maximum context|prompt is too long") {
    return "context_limited"
  }

  if ($text -match "guardrail restrictions and data policy|settings/privacy|No endpoints available matching") {
    return "privacy_policy_blocked"
  }

  if ($text -match "may not exist|may not have access|invalid model|does not exist") {
    return "model_access_error"
  }

  if ($text -match "Provider returned error|temporarily rate-limited upstream|upstream") {
    return "upstream_rate_limited"
  }

  return "other_error"
}

function Get-ModelEvents {
  param(
    [string]$DirectoryPath,
    [datetime]$Since
  )

  $events = @{}

  if (-not (Test-Path $DirectoryPath)) {
    return $events
  }

  $files = Get-ChildItem $DirectoryPath -File -ErrorAction SilentlyContinue |
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

function Get-RouteFallback {
  param(
    [string]$Role,
    [string]$CurrentModel,
    [pscustomobject]$CurrentHealth,
    [hashtable]$RoleOrder,
    [hashtable]$Events,
    [switch]$AllowOpenRouterAuto
  )

  $preferred = @($RoleOrder[$Role])
  if (-not $preferred -or $preferred.Count -eq 0) {
    return $null
  }

  if ($CurrentHealth.status -eq "healthy") {
    return [pscustomobject]@{
      role = $Role
      currentModel = $CurrentModel
      currentStatus = $CurrentHealth.status
      recommendedModel = $CurrentModel
      changed = $false
      reason = "Current model is healthy; no fallback needed."
    }
  }

  foreach ($candidate in $preferred) {
    if ($candidate -eq $CurrentModel) {
      continue
    }

    if (-not $AllowOpenRouterAuto -and $candidate -eq "openrouter,openrouter/auto") {
      continue
    }

    $candidateHealth = Get-ModelHealth -Model $candidate -Events $Events
    if ($candidateHealth.status -eq "healthy") {
      return [pscustomobject]@{
        role = $Role
        currentModel = $CurrentModel
        currentStatus = $CurrentHealth.status
        recommendedModel = $candidate
        changed = $true
        reason = "Current model is $($CurrentHealth.status); first healthy fallback in role order is $candidate."
      }
    }
  }

  return [pscustomobject]@{
    role = $Role
    currentModel = $CurrentModel
    currentStatus = $CurrentHealth.status
    recommendedModel = $null
    changed = $false
    reason = if ($AllowOpenRouterAuto) {
      "Current model is $($CurrentHealth.status); no healthy fallback found in role order."
    } else {
      "Current model is $($CurrentHealth.status); no healthy explicit fallback found and openrouter/auto is skipped unless -AllowOpenRouterAuto is set."
    }
  }
}

function Ensure-Directory {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }

  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Get-EffectiveRoles {
  param(
    [string[]]$RequestedRoles,
    [pscustomobject]$Matrix
  )

  $matrixRoles = @()
  foreach ($property in $Matrix.roles.PSObject.Properties) {
    $matrixRoles += $property.Name
  }

  if (-not $RequestedRoles -or $RequestedRoles.Count -eq 0) {
    return $matrixRoles
  }

  $filtered = @()
  $expanded = @()
  foreach ($item in $RequestedRoles) {
    if ($null -eq $item) {
      continue
    }

    $expanded += ($item -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }

  foreach ($role in $expanded) {
    if ($matrixRoles -contains $role -and $filtered -notcontains $role) {
      $filtered += $role
    }
  }

  return $filtered
}

function New-RouteBackup {
  param(
    [string]$SourcePath,
    [string]$DestinationDir
  )

  Ensure-Directory -Path $DestinationDir

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $fileName = Split-Path $SourcePath -Leaf
  $backupPath = Join-Path $DestinationDir ("{0}.{1}.bak" -f $fileName, $stamp)

  Copy-Item -Path $SourcePath -Destination $backupPath -Force
  return $backupPath
}

$since = (Get-Date).AddHours(-1 * $WindowHours)

if (-not (Test-Path $ConfigPath)) {
  throw "CCR config not found at $ConfigPath"
}

if (-not (Test-Path $MatrixPath)) {
  throw "Route matrix not found at $MatrixPath"
}

$ccrConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$matrix = Get-Content $MatrixPath -Raw | ConvertFrom-Json
$events = Get-ModelEvents -DirectoryPath $LogDir -Since $since
$effectiveRoles = Get-EffectiveRoles -RequestedRoles $Roles -Matrix $matrix
$roleOrder = @{}
foreach ($property in $matrix.roles.PSObject.Properties) {
  $roleOrder[$property.Name] = @($property.Value)
}

$routeRows = @()
$recommendations = @()
$changes = @()

foreach ($role in $effectiveRoles) {
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

  $fallback = Get-RouteFallback -Role $role -CurrentModel $currentModel -CurrentHealth $health -RoleOrder $roleOrder -Events $events -AllowOpenRouterAuto:$AllowOpenRouterAuto
  if ($fallback) {
    $recommendations += $fallback

    if ($fallback.changed -and $fallback.recommendedModel -and $fallback.recommendedModel -ne $currentModel) {
      $changes += [pscustomobject]@{
        role = $role
        from = $currentModel
        to = $fallback.recommendedModel
        reason = $fallback.reason
      }
    }
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
  configPath = $ConfigPath
  matrixPath = $MatrixPath
  logDir = $LogDir
  selectedRoles = $effectiveRoles
  routes = $routeRows
  recommendations = $recommendations
  recentErrors = $eventSummary
  changes = $changes
  applyRequested = [bool]$Apply
  applied = $false
  backupPath = $null
  appliedConfigPath = $null
}

if ($Apply -and $changes.Count -gt 0) {
  if ($PSCmdlet.ShouldProcess($ConfigPath, "Apply $($changes.Count) CCR route change(s)")) {
    $backupPath = New-RouteBackup -SourcePath $ConfigPath -DestinationDir $BackupDir

    foreach ($change in $changes) {
      $ccrConfig.Router.$($change.role) = $change.to
    }

    $tempPath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($ConfigPath), ([System.IO.Path]::GetRandomFileName() + ".json"))
    try {
      ($ccrConfig | ConvertTo-Json -Depth 12) | Set-Content -Path $tempPath -Encoding UTF8
      Move-Item -Path $tempPath -Destination $ConfigPath -Force
      $report.applied = $true
      $report.backupPath = $backupPath
      $report.appliedConfigPath = $ConfigPath
    } finally {
      if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
      }
    }
  }
}

if ($AsJson) {
  $report | ConvertTo-Json -Depth 8
  exit 0
}

Write-Host "CCR route automation"
Write-Host "Generated: $($report.generatedAt)"
Write-Host "Window:    last $WindowHours hour(s)"
Write-Host "Config:    $ConfigPath"
Write-Host ""
Write-Host "Selected roles: $($effectiveRoles -join ', ')"
Write-Host ""
Write-Host "Route health"
if ($report.routes.Count -gt 0) {
  $report.routes | Format-Table -AutoSize role, model, status, httpCode, lastSeen | Out-Host
} else {
  Write-Host "No selected roles were found in the CCR config."
}

Write-Host ""
Write-Host "Fallback recommendations"
if ($report.recommendations.Count -gt 0) {
  foreach ($item in $report.recommendations) {
    if ($item.recommendedModel -and $item.changed) {
      Write-Host "- $($item.role): switch from $($item.currentModel) to $($item.recommendedModel)"
      Write-Host "  $($item.reason)"
    } else {
      Write-Host "- $($item.role): no change"
      Write-Host "  $($item.reason)"
    }
  }
} else {
  Write-Host "No recommendations available for the selected roles."
}

if ($Apply) {
  Write-Host ""
  if ($report.applied) {
    Write-Host "Applied: yes"
    Write-Host "Backup:  $($report.backupPath)"
    Write-Host "Config:  $($report.appliedConfigPath)"
  } else {
    Write-Host "Applied: no"
    if ($changes.Count -eq 0) {
      Write-Host "No route changes were necessary."
    } else {
      Write-Host "Changes were prepared but not written."
    }
  }
} else {
  Write-Host ""
  Write-Host "Dry-run only. Re-run with -Apply to write a backed-up CCR config."
}
