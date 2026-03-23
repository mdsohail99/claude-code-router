[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Selection,
  [switch]$List,
  [switch]$Current,
  [switch]$NoRestart,
  [switch]$NoBackup,
  [switch]$Test,
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
  "free"     = "openrouter,openrouter/free"
}

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return $null
  }

  try {
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
  } catch {
    throw "Unable to parse JSON at $Path"
  }
}

function Write-JsonFile {
  param(
    [string]$Path,
    [object]$Value
  )

  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  $json = $Value | ConvertTo-Json -Depth 20
  Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Backup-File {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return $null
  }

  $backupDir = Join-Path (Split-Path -Parent $Path) "backups"
  if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  }

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $leaf = Split-Path -Leaf $Path
  $backupPath = Join-Path $backupDir ("$leaf.$stamp.bak")
  Copy-Item -Path $Path -Destination $backupPath -Force
  return $backupPath
}

function Read-CcrConfig {
  param([string]$Path)

  $config = Read-JsonFile -Path $Path
  if ($null -eq $config) {
    throw "CCR config not found at $Path"
  }

  return $config
}

function Read-ClaudeSettings {
  param([string]$Path)

  $settings = Read-JsonFile -Path $Path
  if ($null -eq $settings) {
    return [pscustomobject]@{}
  }

  return $settings
}

function Get-CcrModels {
  param([string]$Path)

  $config = Read-CcrConfig -Path $Path
  $items = @()
  foreach ($provider in @($config.Providers)) {
    $providerName = [string]$provider.name
    foreach ($modelId in @($provider.models)) {
      $fullId = "$providerName,$modelId"
      $items += [pscustomobject]@{
        Id = $fullId
        Provider = $providerName
        Model = [string]$modelId
      }
    }
  }

  return $items
}

function Show-CurrentState {
  param(
    [string]$SettingsFile,
    [string]$ConfigFile
  )

  $settings = Read-ClaudeSettings -Path $SettingsFile
  $config = Read-CcrConfig -Path $ConfigFile
  $visible = [string]$settings.model
  $default = [string]$config.Router.default

  Write-Host ""
  Write-Host "Current model state"
  Write-Host ("  Claude visible : {0}" -f (Get-DisplayValue -Value $visible))
  Write-Host ("  CCR default    : {0}" -f (Get-DisplayValue -Value $default))
  Write-Host ""
}

function Get-DisplayValue {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return "<not set>"
  }

  return $Value
}

function Show-ModelList {
  param(
    [string]$ConfigFile,
    [string]$VisibleModel,
    [string]$DefaultModel
  )

  $models = Get-CcrModels -Path $ConfigFile
  Write-Host "Available CCR models"
  for ($i = 0; $i -lt $models.Count; $i++) {
    $item = $models[$i]
    $markers = @()
    if ($item.Id -eq $VisibleModel) {
      $markers += "visible"
    }
    if ($item.Id -eq $DefaultModel) {
      $markers += "default"
    }

    $markerText = ""
    if ($markers.Count -gt 0) {
      $markerText = " [" + ($markers -join ", ") + "]"
    }

    Write-Host ("  {0,2}. {1}{2}" -f ($i + 1), $item.Id, $markerText)
  }
  Write-Host ""
  Write-Host "You can choose by number, preset name, or full model id."
  Write-Host ("Preset shortcuts: {0}" -f (($presets.Keys | Sort-Object) -join ", "))
  Write-Host ""
}

function Resolve-Selection {
  param(
    [string]$RawSelection,
    [string]$ConfigFile
  )

  if (-not $RawSelection) {
    return $null
  }

  $trimmed = $RawSelection.Trim()
  if (-not $trimmed) {
    return $null
  }

  if ($trimmed -match "^\d+$") {
    $index = [int]$trimmed
    $models = Get-CcrModels -Path $ConfigFile
    if ($index -lt 1 -or $index -gt $models.Count) {
      throw "Model number $index is out of range."
    }
    return [string]$models[$index - 1].Id
  }

  $presetKey = $trimmed.ToLowerInvariant()
  if ($presets.Contains($presetKey)) {
    return [string]$presets[$presetKey]
  }

  return $trimmed
}

function Restart-CcrService {
  Write-Host "Restarting CCR..."
  & ccr restart
  if ($LASTEXITCODE -ne 0) {
    throw "CCR restart failed."
  }
}

function Test-ModelReply {
  param([string]$ModelId)

  Write-Host ""
  Write-Host "Running a live reply test..."
  & ccr code --model $ModelId -p "Reply with exactly: ok"
}

$settings = Read-ClaudeSettings -Path $SettingsPath
$config = Read-CcrConfig -Path $CcrConfigPath
$currentVisible = [string]$settings.model
$currentDefault = [string]$config.Router.default

if ($Selection) {
  $normalizedSelection = $Selection.Trim().ToLowerInvariant()
  if ($normalizedSelection -eq "current") {
    $Current = $true
  } elseif ($normalizedSelection -eq "list") {
    $List = $true
  }
}

if ($Current) {
  Show-CurrentState -SettingsFile $SettingsPath -ConfigFile $CcrConfigPath
  exit 0
}

if ($List) {
  Show-CurrentState -SettingsFile $SettingsPath -ConfigFile $CcrConfigPath
  Show-ModelList -ConfigFile $CcrConfigPath -VisibleModel $currentVisible -DefaultModel $currentDefault
  exit 0
}

if (-not $Selection) {
  Show-CurrentState -SettingsFile $SettingsPath -ConfigFile $CcrConfigPath
  Show-ModelList -ConfigFile $CcrConfigPath -VisibleModel $currentVisible -DefaultModel $currentDefault
  $Selection = Read-Host "Select the new default model"
}

$targetModel = Resolve-Selection -RawSelection $Selection -ConfigFile $CcrConfigPath
if (-not $targetModel) {
  throw "No model selected."
}

$settingsBackup = $null
$configBackup = $null
if (-not $NoBackup) {
  $settingsBackup = Backup-File -Path $SettingsPath
  $configBackup = Backup-File -Path $CcrConfigPath
}

$settings.model = $targetModel
$config.Router.default = $targetModel

Write-JsonFile -Path $SettingsPath -Value $settings
Write-JsonFile -Path $CcrConfigPath -Value $config

Write-Host ""
Write-Host "CCR switch applied"
Write-Host ("  Claude visible : {0} -> {1}" -f (Get-DisplayValue -Value $currentVisible), $targetModel)
Write-Host ("  CCR default    : {0} -> {1}" -f (Get-DisplayValue -Value $currentDefault), $targetModel)
if ($settingsBackup) {
  Write-Host ("  Settings backup: {0}" -f $settingsBackup)
}
if ($configBackup) {
  Write-Host ("  Config backup  : {0}" -f $configBackup)
}
Write-Host "  Other CCR routes remain unchanged."

if (-not $NoRestart) {
  Restart-CcrService
}

Show-CurrentState -SettingsFile $SettingsPath -ConfigFile $CcrConfigPath

if ($Test) {
  Test-ModelReply -ModelId $targetModel
}
