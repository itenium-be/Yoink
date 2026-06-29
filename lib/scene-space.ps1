# Scenery renderer: cosmic "space" — starfield + optional nebula + comets.
# New-SpaceStop is the only pure bit (unit-tested); the Add-Space* helpers and
# Start-Space build live WPF visuals. Dot-sourced by show-notification.ps1;
# New-Brush comes from notification-box.ps1.

# Gradient stop with a 0..1 alpha baked into #AARRGGBB (lets nebula/comet gradients
# fade to transparent without a separate Opacity per stop).
function New-SpaceStop([string]$hex6, [double]$alpha, [double]$offset) {
  $a = [int][Math]::Round(255 * $alpha)
  $argb = ('#{0:X2}{1}' -f $a, $hex6.TrimStart('#'))
  New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($argb)), $offset
}

# Scattered stars: mostly white, a few cyan/violet; ~60% twinkle (opacity pulse).
function Add-SpaceStars($canvas, [double]$w, [double]$h, [int]$count) {
  for ($i = 0; $i -lt $count; $i++) {
    $sz = 1.0 + (Get-Random -Minimum 0 -Maximum 25) / 10.0      # 1.0 .. 3.5 px
    $x = (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $w
    $y = (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $h
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $sz; $e.Height = $sz
    $tint = Get-Random -Minimum 0 -Maximum 10
    $col = if ($tint -lt 7) { '#FFFFFF' } elseif ($tint -lt 9) { '#A5F3FC' } else { '#D8B4FE' }
    $e.Fill = New-Brush $col
    [System.Windows.Controls.Canvas]::SetLeft($e, $x); [System.Windows.Controls.Canvas]::SetTop($e, $y)
    $base = 0.55 + (Get-Random -Minimum 0 -Maximum 45) / 100.0  # 0.55 .. 1.0
    $e.Opacity = $base
    $canvas.Children.Add($e) | Out-Null
    # Every star twinkles. Vary the dim floor and period per star; the spread of
    # durations desyncs them within a couple seconds (no BeginTime needed — a negative
    # BeginTime on a BeginAnimation clock does NOT reliably start mid-cycle here).
    $lo = 0.12 + (Get-Random -Minimum 0 -Maximum 20) / 100.0    # dim to 0.12 .. 0.32
    $dur = 0.8 + (Get-Random -Minimum 0 -Maximum 22) / 10.0     # 0.8 .. 3.0 s
    $tw = New-Object System.Windows.Media.Animation.DoubleAnimation $base, $lo, ([System.Windows.Duration][TimeSpan]::FromSeconds($dur))
    $tw.AutoReverse = $true; $tw.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $e.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $tw)
  }
}

# Soft radial nebula blobs in violet/cyan, drifting very slowly.
function Add-SpaceNebula($canvas, [double]$w, [double]$h) {
  foreach ($b in @(
      @{ cx = ($w * 0.28); cy = ($h * 0.38); r = ($h * 0.60); col = '#7C3AED'; op = 0.24; dur = 26 },
      @{ cx = ($w * 0.72); cy = ($h * 0.55); r = ($h * 0.72); col = '#22D3EE'; op = 0.16; dur = 34 },
      @{ cx = ($w * 0.52); cy = ($h * 0.20); r = ($h * 0.46); col = '#A855F7'; op = 0.18; dur = 30 })) {
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $b.r * 2; $e.Height = $b.r * 2
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-SpaceStop $b.col $b.op 0.0))
    $rg.GradientStops.Add((New-SpaceStop $b.col ($b.op * 0.4) 0.5))
    $rg.GradientStops.Add((New-SpaceStop $b.col 0.0 1.0))
    $e.Fill = $rg
    [System.Windows.Controls.Canvas]::SetLeft($e, $b.cx - $b.r); [System.Windows.Controls.Canvas]::SetTop($e, $b.cy - $b.r)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $e.RenderTransform = $tt
    $canvas.Children.Add($e) | Out-Null
    $dx = New-Object System.Windows.Media.Animation.DoubleAnimation 0, ($w * 0.06), ([System.Windows.Duration][TimeSpan]::FromSeconds($b.dur))
    $dx.AutoReverse = $true; $dx.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $dx)
  }
}

function New-DKF([double]$val, [double]$sec) {
  New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $val, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($sec))
}
function New-LoopKF([double]$begin) {
  $a = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
  $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $a.BeginTime = [TimeSpan]::FromSeconds($begin)
  $a
}

# Occasional shooting-star streaks. Each comet is randomized: direction (L->R or
# R->L), start height, slope (up or down), length, thickness, speed and phase. The
# streak's rotation is derived from its actual velocity so the tapered tail always
# trails the head. It holds off-screen, then dashes across (opacity gated so it's
# invisible between passes).
function Add-SpaceComets($canvas, [double]$w, [double]$h) {
  $count = 2 + (Get-Random -Minimum 0 -Maximum 2)   # 2 or 3
  for ($i = 0; $i -lt $count; $i++) {
    $period = 8.0 + (Get-Random -Minimum 0 -Maximum 90) / 10.0          # 8 .. 17 s between passes
    $begin  = (Get-Random -Minimum 0 -Maximum ([int]($period * 10))) / 10.0   # random phase
    $len    = $w * (0.16 + (Get-Random -Minimum 0 -Maximum 16) / 100.0) # 0.16 .. 0.32 w
    $thick  = 2.0 + (Get-Random -Minimum 0 -Maximum 14) / 10.0          # 2.0 .. 3.4
    $startY = $h * (0.05 + (Get-Random -Minimum 0 -Maximum 65) / 100.0) # 0.05 .. 0.70 h
    $dyT    = $h * ((Get-Random -Minimum -30 -Maximum 55) / 100.0)      # slope -0.30 .. +0.54 h
    if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { $startX = -$w * 0.35; $endX = $w * 1.40 }   # L -> R
    else                                          { $startX = $w * 1.35; $endX = -$w * 0.40 }   # R -> L
    $dxT = $endX - $startX
    $angle = [Math]::Atan2($dyT, $dxT) * 180.0 / [Math]::PI

    $rect = New-Object System.Windows.Shapes.Rectangle
    $rect.Width = $len; $rect.Height = $thick; $rect.RadiusX = $thick / 2; $rect.RadiusY = $thick / 2
    $lg = New-Object System.Windows.Media.LinearGradientBrush
    $lg.StartPoint = '0,0'; $lg.EndPoint = '1,0'
    $lg.GradientStops.Add((New-SpaceStop '#FFFFFF' 0.0 0.0))   # tail: transparent
    $lg.GradientStops.Add((New-SpaceStop '#A5F3FC' 0.5 0.7))
    $lg.GradientStops.Add((New-SpaceStop '#FFFFFF' 1.0 1.0))   # head: bright
    $rect.Fill = $lg
    $rect.RenderTransformOrigin = '0.5,0.5'
    $grp = New-Object System.Windows.Media.TransformGroup
    $grp.Children.Add((New-Object System.Windows.Media.RotateTransform $angle))
    $tt = New-Object System.Windows.Media.TranslateTransform
    $grp.Children.Add($tt)
    $rect.RenderTransform = $grp
    [System.Windows.Controls.Canvas]::SetLeft($rect, 0)
    [System.Windows.Controls.Canvas]::SetTop($rect, $startY)
    $rect.Opacity = 0
    $canvas.Children.Add($rect) | Out-Null

    $p = $period
    $kx = New-LoopKF $begin
    $kx.KeyFrames.Add((New-DKF $startX 0))
    $kx.KeyFrames.Add((New-DKF $startX ($p - 1.2)))
    $kx.KeyFrames.Add((New-DKF $endX $p))
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $kx)

    $ky = New-LoopKF $begin
    $ky.KeyFrames.Add((New-DKF 0 0))
    $ky.KeyFrames.Add((New-DKF 0 ($p - 1.2)))
    $ky.KeyFrames.Add((New-DKF $dyT $p))
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $ky)

    $ko = New-LoopKF $begin
    $ko.KeyFrames.Add((New-DKF 0 0))
    $ko.KeyFrames.Add((New-DKF 0 ($p - 1.25)))
    $ko.KeyFrames.Add((New-DKF 1 ($p - 1.0)))
    $ko.KeyFrames.Add((New-DKF 1 ($p - 0.2)))
    $ko.KeyFrames.Add((New-DKF 0 $p))
    $rect.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $ko)
  }
}

# Render the cosmic scene into $box.Scene. $cfg flags: stars / nebula / comets.
# Back (nebula) to front (comets) draw order.
function Start-Space($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }
  $canvas.Width = $w; $canvas.Height = $h

  if ($cfg.nebula) { Add-SpaceNebula $canvas $w $h }
  if ($cfg.stars)  { Add-SpaceStars  $canvas $w $h 60 }
  if ($cfg.comets) { Add-SpaceComets $canvas $w $h }
}
