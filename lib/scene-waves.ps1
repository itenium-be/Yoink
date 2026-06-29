# Scenery renderer: ocean "waves" + optional sky / sun / clouds above the waterline.
# New-WavePathData is WPF-free + unit-tested; the Add-Ocean* helpers and Start-Waves
# build live WPF visuals. Dot-sourced by show-notification.ps1.

# Build XAML path geometry for one wave layer: a sine crest closed down to the
# card's bottom edge so it reads as a filled body of water. The path spans $width
# (caller makes it wider than the card by one period) so a -period horizontal
# scroll loops seamlessly. Coordinates are formatted with the invariant culture:
# XAML requires '.' decimals, but a nl-BE locale would otherwise emit ',' and
# Geometry.Parse would choke.
function New-WavePathData([double]$width, [double]$period, [double]$amp, [double]$top, [double]$bottom, [double]$step) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  if ($step -le 0) { $step = 4 }
  if ($period -le 0) { $period = 1 }
  $sb = New-Object System.Text.StringBuilder
  $x = 0.0; $first = $true
  while ($x -le $width) {
    $y = $top + $amp * [Math]::Sin(2 * [Math]::PI * $x / $period)
    $cmd = if ($first) { 'M' } else { 'L' }
    [void]$sb.Append(("{0} {1},{2} " -f $cmd, $x.ToString('0.##', $ic), $y.ToString('0.##', $ic)))
    $first = $false
    $x += $step
  }
  [void]$sb.Append(("L {0},{1} " -f $width.ToString('0.##', $ic), $bottom.ToString('0.##', $ic)))
  [void]$sb.Append(("L 0,{0} Z" -f $bottom.ToString('0.##', $ic)))
  $sb.ToString()
}

function New-SceneStop([string]$hex, [double]$offset) {
  New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)), $offset
}

# Sky + sea tint. Two continuous gradients (#AARRGGBB) that meet at the horizon so
# there is no transparent band exposing the dark card between the air and the water:
#  - sea: transparent through the upper/text band, deepening to teal toward the bottom
#  - sky: bright air at the very top, faded out before the vertically-centred text
function Add-OceanSky($canvas, [double]$w, [double]$h) {
  $sea = New-Object System.Windows.Shapes.Rectangle
  $sea.Width = $w; $sea.Height = $h
  $sg = New-Object System.Windows.Media.LinearGradientBrush
  $sg.StartPoint = '0,0'; $sg.EndPoint = '0,1'
  $sg.GradientStops.Add((New-SceneStop '#002DD4BF' 0.0))
  $sg.GradientStops.Add((New-SceneStop '#002DD4BF' 0.34))
  $sg.GradientStops.Add((New-SceneStop '#552DD4BF' 0.55))
  $sg.GradientStops.Add((New-SceneStop '#770891B2' 1.0))
  $sea.Fill = $sg
  [System.Windows.Controls.Canvas]::SetLeft($sea, 0); [System.Windows.Controls.Canvas]::SetTop($sea, 0)
  $canvas.Children.Add($sea) | Out-Null

  $sky = New-Object System.Windows.Shapes.Rectangle
  $sky.Width = $w; $sky.Height = $h
  $kg = New-Object System.Windows.Media.LinearGradientBrush
  $kg.StartPoint = '0,0'; $kg.EndPoint = '0,1'
  $kg.GradientStops.Add((New-SceneStop '#CC7DD3FC' 0.0))
  $kg.GradientStops.Add((New-SceneStop '#66BAE6FD' 0.22))
  $kg.GradientStops.Add((New-SceneStop '#0093D7F0' 0.50))
  $sky.Fill = $kg
  [System.Windows.Controls.Canvas]::SetLeft($sky, 0); [System.Windows.Controls.Canvas]::SetTop($sky, 0)
  $canvas.Children.Add($sky) | Out-Null
}

# Soft glowing sun (radial warm gradient) with a slow opacity pulse.
function Add-OceanSun($canvas, [double]$w, [double]$h, [double]$speed) {
  $d = $h * 0.55
  $e = New-Object System.Windows.Shapes.Ellipse
  $e.Width = $d; $e.Height = $d
  $rg = New-Object System.Windows.Media.RadialGradientBrush
  $rg.GradientStops.Add((New-SceneStop '#FFFDE9' 0.0))
  $rg.GradientStops.Add((New-SceneStop '#80FDE047' 0.35))
  $rg.GradientStops.Add((New-SceneStop '#00FDE047' 1.0))
  $e.Fill = $rg
  [System.Windows.Controls.Canvas]::SetLeft($e, $w * 0.14 - $d / 2)
  [System.Windows.Controls.Canvas]::SetTop($e, $h * 0.16 - $d / 2)
  $canvas.Children.Add($e) | Out-Null
  $pulse = New-Object System.Windows.Media.Animation.DoubleAnimation 0.45, 0.65, ([System.Windows.Duration][TimeSpan]::FromSeconds(4.0 / $speed))
  $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $e.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $pulse)
}

# A single cloud: overlapping white ellipses (x,y,w,h in base units, scaled).
function New-CloudVisual([double]$scale) {
  $c = New-Object System.Windows.Controls.Canvas
  $white = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(235, 255, 255, 255))
  foreach ($p in @(@(0, 18, 34, 26), @(20, 8, 46, 40), @(50, 14, 40, 30), @(78, 20, 30, 24))) {
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $p[2] * $scale; $e.Height = $p[3] * $scale; $e.Fill = $white
    [System.Windows.Controls.Canvas]::SetLeft($e, $p[0] * $scale); [System.Windows.Controls.Canvas]::SetTop($e, $p[1] * $scale)
    $c.Children.Add($e) | Out-Null
  }
  $c
}

# Clouds drifting right, randomized in size/height/speed and spread across the
# width via a NEGATIVE animation phase (each starts already part-way through its
# journey), so at t=0 they are scattered instead of clustered at the left edge.
function Add-OceanClouds($canvas, [double]$w, [double]$h, [double]$speed) {
  $n = 4
  for ($i = 0; $i -lt $n; $i++) {
    $scale = 0.55 + (Get-Random -Minimum 0 -Maximum 50) / 100.0   # 0.55 .. 1.05
    $y = $h * (0.05 + (Get-Random -Minimum 0 -Maximum 24) / 100.0) # top ~5% .. 29%
    $dur = 44.0 + (Get-Random -Minimum 0 -Maximum 26)             # 44 .. 70 s travel
    $cloud = New-CloudVisual $scale
    $cloud.Opacity = 0.45 + (Get-Random -Minimum 0 -Maximum 20) / 100.0
    [System.Windows.Controls.Canvas]::SetTop($cloud, $y)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $cloud.RenderTransform = $tt
    $canvas.Children.Add($cloud) | Out-Null
    $cw = 120 * $scale
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation (-$cw), $w, ([System.Windows.Duration][TimeSpan]::FromSeconds($dur / $speed))
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    # Spread the four evenly across the cycle, plus a little jitter.
    $phase = ($i + (Get-Random -Minimum 0 -Maximum 60) / 100.0) / $n
    $anim.BeginTime = [TimeSpan]::FromSeconds( -($phase * $dur / $speed) )
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $anim)
  }
}

# Layered scrolling sine waves along the card bottom (the water itself).
function Add-OceanWaves($canvas, [double]$w, [double]$h, $colors, [double]$opacity, [double]$speed) {
  $layers = @(
    @{ amp = 10; period = ($w * 0.90); top = ($h * 0.78); dur = 13 },
    @{ amp = 8;  period = ($w * 0.60); top = ($h * 0.85); dur = 9 },
    @{ amp = 6;  period = ($w * 0.45); top = ($h * 0.92); dur = 6 }
  )
  for ($i = 0; $i -lt $layers.Count; $i++) {
    $L = $layers[$i]
    $pathW = $w + $L.period   # one extra period so the -period scroll never reveals an edge
    $data = New-WavePathData $pathW $L.period $L.amp $L.top $h ([Math]::Max(4.0, $L.period / 24.0))
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($data)
    $path.Fill = New-Brush ($colors[$i % $colors.Count])
    $path.Opacity = $opacity * 0.6   # per-layer translucency (was canvas-opacity * 0.6)
    [System.Windows.Controls.Canvas]::SetLeft($path, 0)
    [System.Windows.Controls.Canvas]::SetTop($path, 0)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $path.RenderTransform = $tt
    $canvas.Children.Add($path) | Out-Null

    $dur = [System.Windows.Duration][TimeSpan]::FromSeconds($L.dur / $speed)
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-$L.period), $dur
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $anim)
  }
}

# Render the ocean scene into $box.Scene. $cfg: @{ colors; opacity; speed; sky; sun; clouds }.
# Back (sky) to front (waves) draw order. Called from a Loaded handler so the card
# ActualWidth/Height are known.
function Start-Waves($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }

  $colors = @($cfg.colors); if ($colors.Count -eq 0) { $colors = @('#0EA5E9', '#22D3EE', '#2DD4BF') }
  $opacity = [double]$cfg.opacity; if ($opacity -le 0) { $opacity = 0.22 }
  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }

  $canvas.Width = $w; $canvas.Height = $h   # per-element opacity (sky/sun/clouds carry their own)

  if ($cfg.sky)    { Add-OceanSky    $canvas $w $h }
  if ($cfg.sun)    { Add-OceanSun    $canvas $w $h $speed }
  if ($cfg.clouds) { Add-OceanClouds $canvas $w $h $speed }
  Add-OceanWaves $canvas $w $h $colors $opacity $speed
}
