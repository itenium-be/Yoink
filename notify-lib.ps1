# Pure helpers for show-notification.ps1. No WPF — dot-sourceable and unit-testable.

# Read a property from either a hashtable or a (JSON-derived) PSCustomObject.
function Get-Prop($obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  if ($obj -is [hashtable] -or $obj -is [System.Collections.IDictionary]) { return $obj[$name] }
  $p = $obj.PSObject.Properties[$name]
  if ($p) { return $p.Value } else { return $null }
}

# First argument that is neither $null nor an empty string.
function Coalesce {
  foreach ($v in $args) { if ($null -ne $v -and "$v" -ne '') { return $v } }
  return $null
}

# Built-in fallback config — identical to the pre-config hardcoded look.
function Get-NotifyDefaults {
  @{
    activeTheme = 'unicorn'
    events = @{
      'needs-input' = @{ label='Needs you'; accent='#FF7A18'; indicator='👋'; mascot='flag'; sound='exclamation';
        body=@(@{ text='{{folder}}'; style='sub' }) }
      'done' = @{ label='Done!'; accent='#22C55E'; indicator='fireworks'; mascot='confetti'; sound='asterisk';
        body=@(@{ text='{{folder}}'; style='sub' }) }
    }
    themes = @{
      unicorn = @{
        hero='🦄'
        gradient=@('#FF5F6D 0','#FFC371 0.28','#3CFFB0 0.5','#36D1DC 0.72','#A56BFF 1')
        rim=@('#7C3AED 0','#2563EB 0.17','#06B6D4 0.34','#22C55E 0.5','#EAB308 0.67','#F97316 0.84','#EC4899 1')
        card='#18181B'
      }
    }
  }
}

# ["#RRGGBB offset", ...] -> newline-joined <GradientStop/> XAML. Unparseable stops are skipped.
function New-GradientStops([string[]]$stops) {
  $out = foreach ($s in $stops) {
    $parts = (($s -replace '\s+', ' ').Trim()) -split ' '
    if ($parts.Count -lt 2) { continue }
    $color = $parts[0]; $offset = $parts[1]
    if ($color -notmatch '^#[0-9A-Fa-f]{6}$') { continue }
    "<GradientStop Color=`"$color`" Offset=`"$offset`"/>"
  }
  ($out -join "`n")
}

# Load settings.json from $Dir if present; otherwise return built-in defaults. Never throws.
function Get-NotifyConfig([string]$Dir) {
  $path = Join-Path $Dir 'settings.json'
  if (Test-Path $path) {
    try {
      return (Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json)
    } catch {
      Write-Warning "notify: failed to parse settings.json: $($_.Exception.Message)"
    }
  }
  return Get-NotifyDefaults
}

# Enumerate theme names from either shape.
function Get-ThemeNames($cfg) {
  $themes = Get-Prop $cfg 'themes'
  if ($themes -is [hashtable]) { return @($themes.Keys) }
  if ($themes) { return @($themes.PSObject.Properties.Name) }
  return @('unicorn')
}

# Active theme name; "random" picks one of the configured themes.
function Resolve-ThemeName($cfg) {
  $name = Coalesce (Get-Prop $cfg 'activeTheme') 'unicorn'
  if ($name -eq 'random') { $name = Get-ThemeNames $cfg | Get-Random }
  return $name
}

# A theme as a hashtable, every field falling back to the unicorn default.
function Resolve-Theme($cfg, [string]$name) {
  $def = (Get-NotifyDefaults).themes.unicorn
  $t = Get-Prop (Get-Prop $cfg 'themes') $name
  @{
    hero     = (Coalesce (Get-Prop $t 'hero')     $def.hero)
    gradient = @(Coalesce (Get-Prop $t 'gradient') $def.gradient)
    rim      = @(Coalesce (Get-Prop $t 'rim')      $def.rim)
    card     = (Coalesce (Get-Prop $t 'card')     $def.card)
  }
}

# An event as a hashtable, every field falling back to that event's default.
function Resolve-Event($cfg, [string]$event) {
  $defs = (Get-NotifyDefaults).events
  $def = $defs[$event]; if ($null -eq $def) { $def = $defs['done'] }
  $e = Get-Prop (Get-Prop $cfg 'events') $event
  @{
    label     = (Coalesce (Get-Prop $e 'label')     $def.label)
    accent    = (Coalesce (Get-Prop $e 'accent')    $def.accent)
    indicator = (Coalesce (Get-Prop $e 'indicator') $def.indicator)
    mascot    = (Coalesce (Get-Prop $e 'mascot')    $def.mascot)
    sound     = (Coalesce (Get-Prop $e 'sound')     $def.sound)
    body      = @(Coalesce (Get-Prop $e 'body')      $def.body)
  }
}

# ["#RRGGBB offset", ...] -> array of just the "#RRGGBB" colors. Unparseable stops skipped.
function Get-StopColors([string[]]$stops) {
  foreach ($s in $stops) {
    $c = ((($s -replace '\s+', ' ').Trim()) -split ' ')[0]
    if ($c -match '^#[0-9A-Fa-f]{6}$') { $c }
  }
}

# Body templates + context -> cleaned, styled lines.
# Rules: a line whose tokens ALL resolve empty is dropped whole; otherwise dangling
# separator chars are trimmed; empty results are dropped; pure-literal lines are kept.
function Resolve-BodyLines($body, [hashtable]$ctx) {
  $rx = [regex]'\{\{(\w+)\}\}'
  $sep = " `t·-|/".ToCharArray()
  $out = @()
  foreach ($line in $body) {
    $tpl   = [string](Get-Prop $line 'text')
    $style = [string](Get-Prop $line 'style')
    if (@('headline','sub','muted') -notcontains $style) { $style = 'sub' }

    $names = @($rx.Matches($tpl) | ForEach-Object { $_.Groups[1].Value })
    $vals = @{}; $anyVal = $false
    foreach ($n in $names) {
      $v = ''
      if ($ctx.ContainsKey($n)) { $v = [string]$ctx[$n] }
      $vals[$n] = $v
      if ($v -ne '') { $anyVal = $true }
    }
    if ($names.Count -ge 1 -and -not $anyVal) { continue }

    $text = $rx.Replace($tpl, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $vals[$m.Groups[1].Value] })
    $text = ($text -replace '\s+', ' ').Trim().Trim($sep).Trim()
    if ($text -eq '') { continue }
    $out += @{ text = $text; style = $style }
  }
  $out
}
