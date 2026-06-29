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

# Read the enum option lists the editor needs from settings.schema.json.
function Get-SchemaEnums([string]$SchemaPath) {
  $schema = Read-SettingsModel $SchemaPath
  @{
    'mascot.move'  = @(Get-ModelValue $schema @('definitions','event','properties','mascot','properties','move','enum'))
    'mascot.end'   = @(Get-ModelValue $schema @('definitions','event','properties','mascot','properties','end','enum'))
    'sound'        = @(Get-ModelValue $schema @('definitions','event','properties','sound','enum'))
    'scene.glyphs' = @(Get-ModelValue $schema @('definitions','scene','properties','glyphs','enum'))
    'scene.bottom' = @(Get-ModelValue $schema @('definitions','scene','properties','bottom','enum'))
    'scene.base'   = @(Get-ModelValue $schema @('definitions','scene','properties','base','enum'))
  }
}

# Normalize a raw hero value (bare emoji string or { emoji, color | colors }) to
# @{ emoji; colors=@() }. Mirrors Resolve-Theme: "colors" wins, a single "color"
# becomes a one-element list, a bare string carries no colours.
function Get-HeroParts($hero) {
  if ($hero -is [string]) { return @{ emoji = $hero; colors = @() } }
  if ($hero -is [System.Collections.IDictionary]) {
    $cols = @($hero['colors'])
    if (-not $cols -or $cols.Count -eq 0) {
      $one = $hero['color']
      $cols = if ($one) { @($one) } else { @() }
    }
    return @{ emoji = [string]$hero['emoji']; colors = @($cols) }
  }
  @{ emoji = ''; colors = @() }
}

# Inverse of Get-HeroParts for the editor: no colours -> the bare emoji string (the
# common case stays clean); any colours -> the { emoji, colors } object form. Blank
# colour slots are dropped so an empty swatch can't produce colors:[""].
function Build-HeroValue([string]$emoji, $colors) {
  $cols = @(@($colors) | Where-Object { $_ -and "$_".Trim() -ne '' } | ForEach-Object { "$_".Trim() })
  if ($cols.Count -eq 0) { return $emoji }
  [ordered]@{ emoji = $emoji; colors = $cols }
}

# Emoji from a Unicode code point. Emoji literals in a .ps1 are mangled under Windows
# PowerShell 5.1: with no BOM the source is read as the ANSI code page, and bytes like
# 0x92 in 💊 terminate the string literal. Code points keep callers encoding-independent.
function Get-Emoji([int]$codePoint) { [char]::ConvertFromUtf32($codePoint) }

# Curated hero options per theme (emoji + fixed fill colours), shown as a "preset"
# dropdown in the editor. Only themes listed here get the dropdown.
function Get-HeroPresets([string]$theme) {
  $presets = @{
    matrix = @(
      @{ label = 'rabbit'; emoji = (Get-Emoji 0x1F407); colors = @('white') }
      @{ label = 'pill';   emoji = (Get-Emoji 0x1F48A); colors = @('#EF4444', '#3B82F6') }
    )
    spooky = @(
      @{ label = 'pumpkin'; emoji = (Get-Emoji 0x1F383); colors = @('#FFB23A', '#EA5A0C') }
      @{ label = 'ghost';   emoji = (Get-Emoji 0x1F47B); colors = @('#E8E8F2') }
      @{ label = 'skull';   emoji = (Get-Emoji 0x1F480); colors = @('#EDEAD6') }
    )
  }
  if ($presets.ContainsKey($theme)) { @($presets[$theme]) } else { @() }
}

# Ordered list of form-field descriptors for the selected event + theme.
# Each: @{ path=[string[]]; label=string; kind='text'|'dropdown'|'checkbox'|'number'; options=[string[]] }
function Get-EditorFields($model, $enums, [string]$Event, [string]$Theme) {
  $fields = New-Object System.Collections.Generic.List[object]
  function Add-Field($list, $path, $label, $kind, $opts) {
    $list.Add(@{ path = @($path); label = $label; kind = $kind; options = @($opts) })
  }

  $themeNames = @((Get-ModelValue $model @('themes')).Keys)
  Add-Field $fields @('activeTheme') 'activeTheme' 'dropdown' ($themeNames + 'random')

  $ep = @('events', $Event)
  Add-Field $fields ($ep + 'label')               'label'       'text'     @()
  Add-Field $fields ($ep + 'accent')              'accent'      'text'     @()
  Add-Field $fields ($ep + 'indicator')           'indicator'   'text'     @()
  Add-Field $fields ($ep + @('mascot','move'))    'mascot.move' 'dropdown' $enums['mascot.move']
  Add-Field $fields ($ep + @('mascot','end'))     'mascot.end'  'dropdown' $enums['mascot.end']
  Add-Field $fields ($ep + 'sound')               'sound'       'dropdown' $enums['sound']

  $tp = @('themes', $Theme)
  Add-Field $fields ($tp + 'hero') 'hero' 'hero' @()
  Add-Field $fields ($tp + 'card') 'card' 'text' @()

  $scene = Get-ModelValue $model ($tp + 'scene')
  if ($scene -is [System.Collections.IDictionary]) {
    foreach ($k in @($scene.Keys)) {
      if ($k -eq 'kind' -or $k -eq 'colors') { continue }   # readonly / array (deferred)
      $sp = $tp + @('scene', $k)
      $label = "scene.$k"
      $enum = if ($enums.ContainsKey($label)) { @($enums[$label] | Where-Object { $_ }) } else { @() }
      if ($enum.Count)               { Add-Field $fields $sp $label 'dropdown' $enum }
      elseif ($scene[$k] -is [bool]) { Add-Field $fields $sp $label 'checkbox' @() }
      else                           { Add-Field $fields $sp $label 'number' @() }
    }
  }
  $fields
}

# Fixed sample values for {{token}} expansion in the preview (no live session needed).
function Get-SampleContext {
  @{
    folder = 'my-project'; cwd = '/home/wouter/code/my-project'; repo = 'my-project'
    branch = 'main'; dirty = '●'; message = 'Waiting for your input'
    last_prompt = 'add a dark mode toggle'; last_assistant = 'Done — all tests pass'
    model = 'claude-sonnet'; agents = '2'; pending_tool = 'Edit'; permission_mode = 'default'; event = 'done'
  }
}
