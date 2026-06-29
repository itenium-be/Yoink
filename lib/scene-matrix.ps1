# Scenery renderer: "matrix" digital rain — falling glyph columns + optional
# soft vertical glow streaks behind them. Get-MatrixGlyphs / Get-MatrixColumnCount
# are the WPF-free, unit-tested bits; the Add-Matrix* helpers and Start-Matrix
# build live WPF visuals. Dot-sourced by show-notification.ps1; New-Brush comes
# from notification-box.ps1.

# Glyph repertoire per style. Half-width katakana (U+FF66..FF9D) is the iconic
# Matrix look and renders in Consolas; built from code points so this source stays
# pure ASCII (Windows PowerShell reads .ps1 in the locale codepage and would mangle
# raw multibyte glyphs). Unknown/empty falls back to katakana (never empty, so the
# random index in Add-MatrixColumn can't divide by zero).
function Get-MatrixGlyphs([string]$name) {
  $kata = -join (0xFF66..0xFF9D | ForEach-Object { [char]$_ })
  switch (($name + '').ToLowerInvariant()) {
    'latin'  { return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' }
    'digits' { return '0123456789' }
    'binary' { return '01' }
    'mixed'  { return ('0123456789ABCDEF' + $kata) }
    default  { return $kata }
  }
}

# How many glyph columns span the card at the given cell width. Pure + unit-tested.
function Get-MatrixColumnCount([double]$width, [double]$cellW) {
  if ($cellW -le 0) { $cellW = 14 }
  return [Math]::Max(1, [int][Math]::Floor($width / $cellW))
}

# Gradient stop with a 0..1 alpha baked into #AARRGGBB (lets the glow streaks fade
# to transparent at both ends).
function New-MatrixStop([string]$hex6, [double]$alpha, [double]$offset) {
  $a = [int][Math]::Round(255 * $alpha)
  $argb = ('#{0:X2}{1}' -f $a, $hex6.TrimStart('#'))
  New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($argb)), $offset
}

# One falling stream: a vertical run of random glyphs, near-white bright head fading
# up a green tail, scrolling top->bottom forever. Speed + start phase are randomized
# per column so the columns never fall in lockstep. The whole run is built once and
# only its TranslateTransform animates (cheap; no per-frame text mutation).
function Add-MatrixColumn($canvas, [double]$x, [double]$h, [double]$cellW, [string]$glyphs, $colors, [double]$opacity, [double]$speed) {
  $size = $cellW * 1.15
  $trail = 6 + (Get-Random -Minimum 0 -Maximum 12)        # 6..17 glyphs
  $head = '#FFFFFF'                                        # bright leading glyph
  $body = $colors[$colors.Count - 1]
  $stack = New-Object System.Windows.Controls.StackPanel
  $stack.Orientation = 'Vertical'
  for ($i = 0; $i -lt $trail; $i++) {
    $ch = $glyphs[(Get-Random -Minimum 0 -Maximum $glyphs.Length)]
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = [string]$ch
    $t.FontFamily = New-Object System.Windows.Media.FontFamily 'Consolas'
    $t.FontSize = $size
    $t.Width = $size; $t.TextAlignment = 'Center'; $t.LineHeight = $size; $t.LineStackingStrategy = 'BlockLineHeight'
    $isHead = ($i -eq $trail - 1)                          # head falls at the bottom of the run
    $t.Foreground = New-Brush ($(if ($isHead) { $head } else { $body }))
    # Tail fades out toward the top (i=0); head is fully opaque for the glow.
    $frac = ($i + 1) / $trail
    $t.Opacity = $opacity * ($(if ($isHead) { 1.0 } else { 0.12 + 0.78 * $frac }))
    $stack.Children.Add($t) | Out-Null
  }
  [System.Windows.Controls.Canvas]::SetLeft($stack, $x)
  $tt = New-Object System.Windows.Media.TranslateTransform
  $stack.RenderTransform = $tt
  $canvas.Children.Add($stack) | Out-Null

  $trailPx = $trail * $size
  $dur = (5.0 + (Get-Random -Minimum 0 -Maximum 60) / 10.0) / $speed   # ~5..11 s fall
  $anim = New-Object System.Windows.Media.Animation.DoubleAnimation (-$trailPx), $h, ([System.Windows.Duration][TimeSpan]::FromSeconds($dur))
  $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  # Negative start so columns are scattered down the card at t=0, not all up top.
  $anim.BeginTime = [TimeSpan]::FromSeconds( -((Get-Random -Minimum 0 -Maximum 100) / 100.0) * $dur )
  $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
}

# The rain itself: a stream per column, thinned by $density (0..1 fraction of
# columns that get a stream) so the field looks irregular rather than solid.
function Add-MatrixRain($canvas, [double]$w, [double]$h, [double]$cellW, [string]$glyphs, $colors, [double]$opacity, [double]$speed, [double]$density) {
  $cols = Get-MatrixColumnCount $w $cellW
  for ($c = 0; $c -lt $cols; $c++) {
    if ((Get-Random -Minimum 0 -Maximum 1000) / 1000.0 -gt $density) { continue }
    Add-MatrixColumn $canvas ($c * $cellW) $h $cellW $glyphs $colors $opacity $speed
  }
}

# Optional ambience: a few soft, wide vertical green glow bands sliding down behind
# the rain to add depth (transparent->green->transparent along Y).
function Add-MatrixStreaks($canvas, [double]$w, [double]$h, $colors, [double]$speed) {
  $glow = $colors[0]
  $n = 5
  for ($i = 0; $i -lt $n; $i++) {
    $bw = $w * (0.05 + (Get-Random -Minimum 0 -Maximum 70) / 1000.0)   # 5%..12% wide
    $rect = New-Object System.Windows.Shapes.Rectangle
    $rect.Width = $bw; $rect.Height = $h
    $lg = New-Object System.Windows.Media.LinearGradientBrush
    $lg.StartPoint = '0,0'; $lg.EndPoint = '0,1'
    $lg.GradientStops.Add((New-MatrixStop $glow 0.0  0.0))
    $lg.GradientStops.Add((New-MatrixStop $glow 0.16 0.5))
    $lg.GradientStops.Add((New-MatrixStop $glow 0.0  1.0))
    $rect.Fill = $lg
    [System.Windows.Controls.Canvas]::SetLeft($rect, (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $w)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $rect.RenderTransform = $tt
    $canvas.Children.Add($rect) | Out-Null
    $dur = (10.0 + (Get-Random -Minimum 0 -Maximum 80) / 10.0) / $speed
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation (-$h), $h, ([System.Windows.Duration][TimeSpan]::FromSeconds($dur))
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $anim.BeginTime = [TimeSpan]::FromSeconds( -(($i + (Get-Random -Minimum 0 -Maximum 80) / 100.0) / $n) * $dur )
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
  }
}

# Render the matrix scene into $box.Scene. cfg keys: colors, opacity, speed, glyphs,
# density, streaks. Streaks (back) then rain (front). Called from a Loaded handler
# so the card ActualWidth/Height are known.
function Start-Matrix($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }
  $canvas.Width = $w; $canvas.Height = $h

  $colors = @($cfg.colors); if ($colors.Count -eq 0) { $colors = @('#39FF14', '#00FF41', '#16A34A') }
  $opacity = [double]$cfg.opacity; if ($opacity -le 0) { $opacity = 0.9 }   # glyphs need to read, unlike translucent waves
  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }
  $density = [double]$cfg.density; if ($density -le 0) { $density = 0.85 }; if ($density -gt 1) { $density = 1.0 }
  $glyphs = Get-MatrixGlyphs ([string]$cfg.glyphs)
  $cellW = [Math]::Max(12.0, $h * 0.085)

  if ($cfg.streaks) { Add-MatrixStreaks $canvas $w $h $colors $speed }
  Add-MatrixRain $canvas $w $h $cellW $glyphs $colors $opacity $speed $density
}
