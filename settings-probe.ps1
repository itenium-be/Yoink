# Bash-readable probe of the user settings.json. Prints key=value lines:
#   status=ok|error   error=<message>   off-behavior=bell,sound
# The only path by which bash learns anything from the JSONC settings file.
# -FallbackDir mirrors Get-NotifyConfig's bundled tier, so the off-behavior default
# honors a plugin-shipped settings.json rather than always hardcoding bell.
param([string]$SettingsDir = "", [string]$FallbackDir = "")
. (Join-Path $PSScriptRoot 'notify-lib.ps1')

# A broken USER file is a doctor-facing error (the "/yoink doctor" check this backs
# depends on it) — so only the user tier throws. A broken BUNDLED file is a packaging
# issue, not the user's, and is skipped silently just like Get-NotifyConfig's own
# try/catch does for every tier.
$path = if ($SettingsDir) { Join-Path $SettingsDir 'settings.json' } else { '' }
if ($path -and (Test-Path $path)) {
  try {
    $raw = Remove-JsonComments (Get-Content -Raw -Encoding UTF8 $path)
    $cfg = $raw | ConvertFrom-Json
  } catch {
    Write-Output "status=error"
    Write-Output ("error=" + ($_.Exception.Message -replace '\r?\n', ' '))
    exit 0
  }
} else {
  $cfg = $null
  $fallbackPath = if ($FallbackDir) { Join-Path $FallbackDir 'settings.json' } else { '' }
  if ($fallbackPath -and (Test-Path $fallbackPath)) {
    try {
      $raw = Remove-JsonComments (Get-Content -Raw -Encoding UTF8 $fallbackPath)
      $cfg = $raw | ConvertFrom-Json
    } catch {
      $cfg = $null
    }
  }
}
Write-Output "status=ok"
Write-Output ("off-behavior=" + ((Get-OffBehavior $cfg) -join ','))
