# Pure model layer for settings-editor.ps1. No WPF — dot-sourceable and unit-testable.
. (Join-Path $PSScriptRoot '..\notify-lib.ps1')   # Remove-JsonComments

# JSON-derived PSCustomObject/array -> ordered hashtable / array, recursively. Ordered so
# Save keeps a stable key order.
function ConvertTo-HashtableDeep($obj) {
  if ($obj -is [System.Management.Automation.PSCustomObject]) {
    $h = [ordered]@{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }
    return $h
  }
  if ($obj -is [System.Collections.IList] -and $obj -isnot [string]) {
    return @($obj | ForEach-Object { ConvertTo-HashtableDeep $_ })
  }
  return $obj
}

# Load a JSON (or JSONC) file into a deep ordered-hashtable model.
function Read-SettingsModel([string]$Path) {
  $raw = Remove-JsonComments (Get-Content -Raw -Encoding UTF8 $Path)
  ConvertTo-HashtableDeep ($raw | ConvertFrom-Json)
}

# Read a nested value by path; $null if any segment is missing.
function Get-ModelValue($model, [string[]]$Path) {
  $cur = $model
  foreach ($k in $Path) {
    if ($null -eq $cur -or -not ($cur -is [System.Collections.IDictionary])) { return $null }
    $cur = $cur[$k]
  }
  $cur
}

# Set a nested value by path, creating intermediate ordered hashtables as needed.
function Set-ModelValue($model, [string[]]$Path, $Value) {
  $cur = $model
  for ($i = 0; $i -lt $Path.Count - 1; $i++) {
    $k = $Path[$i]
    if ($null -eq $cur[$k] -or -not ($cur[$k] -is [System.Collections.IDictionary])) { $cur[$k] = [ordered]@{} }
    $cur = $cur[$k]
  }
  $cur[$Path[$Path.Count - 1]] = $Value
}

# Model -> pretty JSON string for Save (comments are not preserved).
function ConvertTo-SettingsJson($model) {
  $model | ConvertTo-Json -Depth 12
}

# Coerce a raw control value to the type implied by a field kind.
function ConvertTo-ModelValue([string]$Kind, $Raw) {
  switch ($Kind) {
    'checkbox' { return [bool]$Raw }
    'number'   {
      if ([string]$Raw -match '^-?\d+$') { return [int]$Raw }
      $d = 0.0
      # Invariant culture: JSON numbers are '.'-decimal regardless of the host locale.
      if ([double]::TryParse([string]$Raw, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
      return $Raw
    }
    default    { return [string]$Raw }
  }
}
