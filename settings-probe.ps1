# Bash-readable probe of the user settings.json. Prints key=value lines:
#   status=ok|error   error=<message>   off-behavior=bell,sound
# The only path by which bash learns anything from the JSONC settings file.
param([string]$SettingsDir = "")
. (Join-Path $PSScriptRoot 'notify-lib.ps1')

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
}
Write-Output "status=ok"
Write-Output ("off-behavior=" + ((Get-OffBehavior $cfg) -join ','))
