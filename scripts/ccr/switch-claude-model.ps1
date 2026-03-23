[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$Preset,
  [string]$Model,
  [int]$ModelIndex,
  [string]$RouteRole,
  [switch]$UseCcrDefault,
  [switch]$ListPresets,
  [switch]$ListCcrModels,
  [switch]$NoBackup,
  [string]$SettingsPath = (Join-Path $env:USERPROFILE ".claude\settings.json"),
  [string]$CcrConfigPath = (Join-Path $env:USERPROFILE ".claude-code-router\config.json")
)

$ErrorActionPreference = "Stop"

$presets = [ordered]@{
  "nemotron" = "openrouter,nvidia/nemotron-3-super-120b-a12b:free"
  "gemma"    = "openrouter,google/gemma-3-27b-it:free"
  "minimax"  = "openrouter,minimax/minimax-m2.5:free"
  "trinity"  = "openrouter,arcee-ai/trinity-large-preview:free"
  "step"     = "openrouter,stepfun/step-3.5-flash:free"
  "image"    = "openrouter,nvidia/nemotron-nano-12b-v2-vl:free"
  "coder"    = "openrouter,qwen/qwen3-coder:free"
  "auto"     = "openrouter,openrouter/auto"
}

function Show-Presets {
  Write-Host "Claude Code model presets"
  foreach ($entry in $presets.GetEnumerator()) {
    Write-Host ("  {0,-10} -> {1}" -f $entry.Key, $entry.Value)
  }
  Write-Host ""
  Write-Host "Use either a preset name or an explicit OpenRouter model id."
  Write-Host "You can also use -UseCcrDefault, -RouteRole <role>, -ListCcrModels, or -ModelIndex <number>."
}

function Read-CcrConfig {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "CCR config not found at $Path"
  }

  try {
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
  } catch {
    throw "Unable to parse CCR config at $Path."
  }
}

function Get-CcrModels {
  param([string]$Path)

  $config = Read-CcrConfig -Path $Path
  $models = @()
  foreach ($provider in @($config.Providers)) {
    $providerName = [string]$provider.name
    foreach ($modelId in @($provider.models)) {
      $models += [pscustomobject]@{
        provider = $providerName
        id = "openrouter,$modelId"
        shortId = [string]$modelId
      }
    }
  }

  return $models
}

function Show-CcrModels {
  param([string]$Path)

  $models = Get-CcrModels -Path $Path
  Write-Host "CCR OpenRouter models"
  $index = 1
  foreach ($item in $models) {
    Write-Host ("  {0,2}. {1}" -f $index, $item.id)
    $index++
  }
  Write-Host ""
  Write-Host "Use -ModelIndex <number> to switch by list position."
}

function Resolve-ModelId {
  param(
    [string]$PresetName,
    [string]$ExplicitModel,
    [int]$SelectedModelIndex,
    [string]$SelectedRouteRole,
    [bool]$UseCurrentCcrDefault,
    [string]$RouterConfigPath
  )

  $sourceCount = @(
    [bool]$PresetName,
    [bool]$ExplicitModel,
    ($SelectedModelIndex -gt 0),
    [bool]$SelectedRouteRole,
    $UseCurrentCcrDefault
  ) | Where-Object { $_ }

  if ($sourceCount.Count -gt 1) {
    throw "Specify only one of -Preset, -Model, -ModelIndex, -RouteRole, or -UseCcrDefault."
  }

  if ($ExplicitModel) {
    return $ExplicitModel.Trim()
  }

  if ($SelectedModelIndex -gt 0) {
    $models = Get-CcrModels -Path $RouterConfigPath
    if ($SelectedModelIndex -gt $models.Count) {
      throw "Model index $SelectedModelIndex is out of range. Run -ListCcrModels first."
    }
    return [string]$models[$SelectedModelIndex - 1].id
  }

  if ($PresetName) {
    $key = $PresetName.Trim().ToLowerInvariant()
    if (-not $presets.Contains($key)) {
      $valid = ($presets.Keys | Sort-Object) -join ", "
      throw "Unknown preset '$PresetName'. Valid presets: $valid"
    }
    return $presets[$key]
  }

  $resolvedRouteRole = $SelectedRouteRole
  if ($UseCurrentCcrDefault) {
    $resolvedRouteRole = "default"
  }

  if ($resolvedRouteRole) {
    $routerConfig = Read-CcrConfig -Path $RouterConfigPath

    $routeModel = [string]$routerConfig.Router.$resolvedRouteRole
    if (-not $routeModel) {
      throw "CCR route '$resolvedRouteRole' is not set in $RouterConfigPath."
    }

    return $routeModel
  }

  return $null
}

function Read-SettingsJson {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return [pscustomobject]@{}
  }

  try {
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
  } catch {
    throw "Unable to parse JSON at $Path. Fix the file before switching models."
  }
}

function Backup-SettingsFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return $null
  }

  $backupDir = Join-Path (Split-Path -Parent $Path) "backups"
  if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  }

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupPath = Join-Path $backupDir ("settings.json." + $stamp + ".bak")
  Copy-Item -Path $Path -Destination $backupPath -Force
  return $backupPath
}

if ($ListPresets) {
  Show-Presets
  exit 0
}

if ($ListCcrModels) {
  Show-CcrModels -Path $CcrConfigPath
  exit 0
}

$targetModel = Resolve-ModelId -PresetName $Preset -ExplicitModel $Model -SelectedModelIndex $ModelIndex -SelectedRouteRole $RouteRole -UseCurrentCcrDefault $UseCcrDefault -RouterConfigPath $CcrConfigPath

if (-not $targetModel) {
  Show-Presets
  Write-Host ""
  Show-CcrModels -Path $CcrConfigPath
  $choice = Read-Host "Enter preset name, route role, model number, or explicit model id"
  if ($choice -match "^\d+$") {
    $targetModel = Resolve-ModelId -SelectedModelIndex ([int]$choice) -RouterConfigPath $CcrConfigPath
  } elseif ($choice -match "^[A-Za-z0-9._-]+$" -and $presets.Contains($choice.ToLowerInvariant())) {
    $targetModel = $presets[$choice.ToLowerInvariant()]
  } elseif ($choice -match "^(default|background|think|longContext|webSearch|image|code)$") {
    $targetModel = Resolve-ModelId -SelectedRouteRole $choice -RouterConfigPath $CcrConfigPath
  } else {
    $targetModel = $choice.Trim()
  }
}

if (-not $targetModel) {
  throw "No model selected."
}

$settings = Read-SettingsJson -Path $SettingsPath
$currentModel = [string]$settings.model

if ($currentModel -eq $targetModel) {
  Write-Host "Claude Code is already using: $targetModel"
  exit 0
}

$backupPath = $null
if (-not $NoBackup) {
  $backupPath = Backup-SettingsFile -Path $SettingsPath
}

if ($PSCmdlet.ShouldProcess($SettingsPath, "Set Claude Code model to $targetModel")) {
  $settings | Add-Member -NotePropertyName model -NotePropertyValue $targetModel -Force
  $settingsJson = $settings | ConvertTo-Json -Depth 12

  $settingsDir = Split-Path -Parent $SettingsPath
  if ($settingsDir -and -not (Test-Path $settingsDir)) {
    New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
  }

  Set-Content -Path $SettingsPath -Value $settingsJson -Encoding UTF8

  Write-Host "Claude Code model updated."
  Write-Host ("  Current : {0}" -f $currentModel)
  Write-Host ("  New     : {0}" -f $targetModel)
  Write-Host ("  Saved to: {0}" -f $SettingsPath)
  if ($backupPath) {
    Write-Host ("  Backup  : {0}" -f $backupPath)
  }
}
