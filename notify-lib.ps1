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
      'needs-input' = @{ label='Needs you'; accent='#FF7A18'; indicator='👋'; mascot=@{ move='walk'; end='flag' }; sound='exclamation';
        body=@(@{ text='{{folder}}'; style='sub' }); footer=@() }
      'done' = @{ label='Done!'; accent='#22C55E'; indicator='fireworks'; mascot=@{ move='walk'; end='confetti' }; sound='asterisk';
        body=@(@{ text='{{folder}}'; style='sub' }); footer=@() }
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

# Plain colours (hex or a WPF named colour) -> hard-banded <GradientStop/> XAML: each
# colour fills an equal, sharp-edged slice of the hero silhouette, so two colours give
# a clean 50/50 split (the red/blue pill) and one colour gives a solid fill. Unlike
# New-GradientStops, the inputs carry no offsets. Invalid tokens are skipped, which
# also blocks XAML injection via the colour string.
function New-HeroStops([string[]]$colors) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $valid = @($colors | Where-Object { $_ -match '^#[0-9A-Fa-f]{6}$' -or $_ -match '^[A-Za-z]+$' })
  $n = $valid.Count
  if ($n -eq 0) { return '' }
  $out = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $n; $i++) {
    $lo = ($i / [double]$n).ToString('0.####', $ic)
    $hi = (($i + 1) / [double]$n).ToString('0.####', $ic)
    $out.Add("<GradientStop Color=`"$($valid[$i])`" Offset=`"$lo`"/>")
    $out.Add("<GradientStop Color=`"$($valid[$i])`" Offset=`"$hi`"/>")
  }
  ($out -join "`n")
}

# Strip // line and /* block */ comments so settings.json can be annotated (JSONC).
# Windows PowerShell's ConvertFrom-Json has no -AllowComments. String-aware: a // or
# /* inside a "string" (e.g. an https:// URL) is left intact, and \" doesn't end the
# string. Trailing commas are NOT handled — this only removes comments.
function Remove-JsonComments([string]$text) {
  $sb = New-Object System.Text.StringBuilder
  $inStr = $false; $esc = $false; $line = $false; $block = $false
  for ($i = 0; $i -lt $text.Length; $i++) {
    $c = $text[$i]
    $n = if ($i + 1 -lt $text.Length) { $text[$i + 1] } else { [char]0 }
    if ($line)  { if ($c -eq "`n") { $line = $false; [void]$sb.Append($c) }; continue }
    if ($block) { if ($c -eq '*' -and $n -eq '/') { $block = $false; $i++ }; continue }
    if ($inStr) {
      [void]$sb.Append($c)
      if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
      continue
    }
    if ($c -eq '"') { $inStr = $true; [void]$sb.Append($c); continue }
    if ($c -eq '/' -and $n -eq '/') { $line = $true; $i++; continue }
    if ($c -eq '/' -and $n -eq '*') { $block = $true; $i++; continue }
    [void]$sb.Append($c)
  }
  $sb.ToString()
}

# Load settings.json from $Dir if present; otherwise return built-in defaults. Never throws.
function Get-NotifyConfig([string]$Dir) {
  $path = Join-Path $Dir 'settings.json'
  if (Test-Path $path) {
    try {
      return (Remove-JsonComments (Get-Content -Raw -Encoding UTF8 $path) | ConvertFrom-Json)
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

  # hero is either a bare emoji string or an object { emoji, color | colors }. The
  # object form recolours the silhouette (heroColors); a string keeps the default
  # gradient fill (heroColors stays $null).
  $rawHero = Get-Prop $t 'hero'
  $heroEmoji = $def.hero; $heroColors = $null
  if ($rawHero -is [string] -and $rawHero -ne '') {
    $heroEmoji = $rawHero
  } elseif ($rawHero) {
    $heroEmoji = (Coalesce (Get-Prop $rawHero 'emoji') $def.hero)
    $cols = @(Get-Prop $rawHero 'colors')
    if (-not $cols -or $cols.Count -eq 0) {
      $one = Get-Prop $rawHero 'color'
      $cols = if ($one) { @($one) } else { @() }
    }
    if ($cols.Count -gt 0) { $heroColors = @($cols) }
  }

  @{
    hero       = $heroEmoji
    heroColors = $heroColors
    gradient   = @(Coalesce (Get-Prop $t 'gradient') $def.gradient)
    rim        = @(Coalesce (Get-Prop $t 'rim')      $def.rim)
    card       = (Coalesce (Get-Prop $t 'card')     $def.card)
    scene      = (Get-Prop $t 'scene')
  }
}

# An event as a hashtable, every field falling back to that event's default.
function Resolve-Event($cfg, [string]$event) {
  $defs = (Get-NotifyDefaults).events
  $def = $defs[$event]; if ($null -eq $def) { $def = $defs['done'] }
  $e = Get-Prop (Get-Prop $cfg 'events') $event
  # indicator / sound: an explicit "" is honored as-is (no badge / no sound); only a
  # MISSING key (null) falls back to the default. (Coalesce can't tell "" from absent.)
  $ind = Get-Prop $e 'indicator'; if ($null -eq $ind) { $ind = $def.indicator }
  $snd = Get-Prop $e 'sound';     if ($null -eq $snd) { $snd = $def.sound }
  $ftr = Get-Prop $e 'footer';    if ($null -eq $ftr) { $ftr = $def.footer }
  @{
    label     = (Coalesce (Get-Prop $e 'label')     $def.label)
    accent    = (Coalesce (Get-Prop $e 'accent')    $def.accent)
    indicator = [string]$ind
    mascot    = @{
      move = (Coalesce (Get-Prop (Get-Prop $e 'mascot') 'move') $def.mascot.move)
      end  = (Coalesce (Get-Prop (Get-Prop $e 'mascot') 'end')  $def.mascot.end)
    }
    sound     = [string]$snd
    body      = @(Coalesce (Get-Prop $e 'body')      $def.body)
    footer    = @($ftr)
  }
}

# ["#RRGGBB offset", ...] -> array of just the "#RRGGBB" colors. Unparseable stops skipped.
function Get-StopColors([string[]]$stops) {
  foreach ($s in $stops) {
    $c = ((($s -replace '\s+', ' ').Trim()) -split ' ')[0]
    if ($c -match '^#[0-9A-Fa-f]{6}$') { $c }
  }
}

# Expand {{tokens}} in $tpl against $ctx. Returns the cleaned string, or $null when the
# template HAS tokens that ALL resolve empty (caller drops it). Dangling separator chars
# are trimmed; a pure-literal template is always kept.
function Expand-Template([string]$tpl, [hashtable]$ctx) {
  $rx = [regex]'\{\{(\w+)\}\}'
  $sep = " `t·-|/".ToCharArray()
  $names = @($rx.Matches($tpl) | ForEach-Object { $_.Groups[1].Value })
  $vals = @{}; $anyVal = $false
  foreach ($n in $names) {
    $v = ''
    if ($ctx.ContainsKey($n)) { $v = [string]$ctx[$n] }
    $vals[$n] = $v
    if ($v -ne '') { $anyVal = $true }
  }
  if ($names.Count -ge 1 -and -not $anyVal) { return $null }
  $text = $rx.Replace($tpl, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $vals[$m.Groups[1].Value] })
  $text = ($text -replace '\s+', ' ').Trim().Trim($sep).Trim()
  if ($text -eq '') { return $null }
  return $text
}

# Body templates + context -> cleaned, styled lines (a dropped template is skipped).
function Resolve-BodyLines($body, [hashtable]$ctx) {
  $out = @()
  foreach ($line in $body) {
    $text = Expand-Template ([string](Get-Prop $line 'text')) $ctx
    if ($null -eq $text) { continue }
    $style = [string](Get-Prop $line 'style')
    if (@('headline','sub','muted') -notcontains $style) { $style = 'sub' }
    $out += @{ text = $text; style = $style }
  }
  $out
}

# Footer badge templates + context -> cleaned badges. A badge whose tokens all resolve
# empty is dropped; color/background pass through verbatim ("" -> renderer default).
function Resolve-Footer($footer, [hashtable]$ctx) {
  $out = @()
  foreach ($b in $footer) {
    $text = Expand-Template ([string](Get-Prop $b 'badge')) $ctx
    if ($null -eq $text) { continue }
    $out += @{ text = $text; color = [string](Get-Prop $b 'color'); background = [string](Get-Prop $b 'background') }
  }
  $out
}
