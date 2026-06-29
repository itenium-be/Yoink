# Scenery renderer: dragon — rising embers + optional fire glow, flame tongues and
# smoke wisps. New-FlamePathData / New-DragonStop are the pure bits (unit-tested);
# the Add-Dragon* helpers and Start-Dragon build live WPF visuals. Dot-sourced by
# show-notification.ps1; New-Brush comes from notification-box.ps1.

# A faceted gem outline as XAML path geometry: a flat table along the top, girdle
# corners at the sides, tapering to a pointed pavilion at the bottom. Coordinates are
# SPACE-separated and formatted with the invariant culture (the nl-BE machine locale
# would emit ',' decimals and Geometry.Parse would choke — see New-WavePathData).
function New-GemPathData([double]$w, [double]$h) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $n = { param($v) ([double]$v).ToString('0.###', $ic) }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("M $(& $n ($w*0.22)) $(& $n 0) ")     # table left
  [void]$sb.Append("L $(& $n ($w*0.78)) $(& $n 0) ")     # table right
  [void]$sb.Append("L $(& $n $w) $(& $n ($h*0.34)) ")    # right girdle
  [void]$sb.Append("L $(& $n ($w*0.5)) $(& $n $h) ")     # culet (bottom point)
  [void]$sb.Append("L $(& $n 0) $(& $n ($h*0.34)) ")     # left girdle
  [void]$sb.Append('Z')
  $sb.ToString()
}

# A 4-point sparkle star (concave between the points) of size $s, as XAML path
# geometry. Same invariant-culture, space-separated convention as above.
function New-GlintPathData([double]$s) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $n = { param($v) ([double]$v).ToString('0.###', $ic) }
  $c = $s / 2.0; $i = $s * 0.14   # inner concave radius
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("M $(& $n $c) $(& $n 0) ")
  [void]$sb.Append("L $(& $n ($c+$i)) $(& $n ($c-$i)) L $(& $n $s) $(& $n $c) ")
  [void]$sb.Append("L $(& $n ($c+$i)) $(& $n ($c+$i)) L $(& $n $c) $(& $n $s) ")
  [void]$sb.Append("L $(& $n ($c-$i)) $(& $n ($c+$i)) L $(& $n 0) $(& $n $c) ")
  [void]$sb.Append("L $(& $n ($c-$i)) $(& $n ($c-$i)) ")
  [void]$sb.Append('Z')
  $sb.ToString()
}

# Gradient stop with a 0..1 alpha baked into #AARRGGBB (lets the glow/flame gradients
# fade to transparent without a separate Opacity per stop). Mirrors New-SpaceStop.
function New-DragonStop([string]$hex6, [double]$alpha, [double]$offset) {
  $a = [int][Math]::Round(255 * $alpha)
  $argb = ('#{0:X2}{1}' -f $a, $hex6.TrimStart('#'))
  New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($argb)), $offset
}

# Fire spark tints, hottest (white-yellow) to coolest (deep orange).
$script:DragonEmberColors = @('#FFF3B0', '#FDE047', '#FBBF24', '#F97316', '#FB923C')

# A seamless vertical loop on a TranslateTransform.Y from $yStart to $yEnd, started
# mid-cycle at $phase (0..1) so elements scatter without a negative BeginTime
# (unreliable). The wrap is a discrete jump but happens off-card (both ends are past
# the edges). Works either direction: embers rise (yStart>yEnd), petals fall.
function Add-VertLoop($tt, [double]$yStart, [double]$yEnd, [double]$dur, [double]$phase) {
  $span = $yEnd - $yStart
  $startV = $yStart + $phase * $span
  $t1 = $dur * (1 - $phase)
  $kf = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
  $kf.Duration = [System.Windows.Duration][TimeSpan]::FromSeconds($dur)
  $kf.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $kf.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $startV, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds(0)))) | Out-Null
  $kf.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $yEnd, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($t1)))) | Out-Null
  $kf.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteDoubleKeyFrame $yStart, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($t1)))) | Out-Null
  $kf.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $startV, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($dur)))) | Out-Null
  $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $kf)
}

# Glowing spark particles rising from the bottom, swaying and flickering. Flicker is a
# ScaleTransform pulse (the star-twinkle trick): a plain Opacity BeginAnimation does
# not repaint reliably for scene children here, but render-transform animations do.
function Add-DragonEmbers($canvas, [double]$w, [double]$h, [int]$count, [double]$speed) {
  for ($i = 0; $i -lt $count; $i++) {
    $sz = 2.0 + (Get-Random -Minimum 0 -Maximum 35) / 10.0          # 2.0 .. 5.5 px
    $col = $script:DragonEmberColors[(Get-Random -Minimum 0 -Maximum $script:DragonEmberColors.Count)]
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $sz; $e.Height = $sz
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-DragonStop $col 1.0 0.0))
    $rg.GradientStops.Add((New-DragonStop $col 0.6 0.5))
    $rg.GradientStops.Add((New-DragonStop $col 0.0 1.0))
    $e.Fill = $rg
    $e.Opacity = 0.6 + (Get-Random -Minimum 0 -Maximum 40) / 100.0  # 0.6 .. 1.0

    $startX = (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $w
    [System.Windows.Controls.Canvas]::SetLeft($e, $startX); [System.Windows.Controls.Canvas]::SetTop($e, 0)
    $sc = New-Object System.Windows.Media.ScaleTransform 1, 1
    $sc.CenterX = $sz / 2; $sc.CenterY = $sz / 2
    $tt = New-Object System.Windows.Media.TranslateTransform
    $grp = New-Object System.Windows.Media.TransformGroup
    $grp.Children.Add($sc); $grp.Children.Add($tt)
    $e.RenderTransform = $grp
    $canvas.Children.Add($e) | Out-Null

    # Rise from just below the bottom to just above the top.
    $dur = (5.0 + (Get-Random -Minimum 0 -Maximum 70) / 10.0) / $speed   # 5 .. 12 s
    Add-VertLoop $tt ($h + $sz) (-$sz) $dur ((Get-Random -Minimum 0 -Maximum 1000) / 1000.0)

    $amp = 6 + (Get-Random -Minimum 0 -Maximum 14)
    $sdur = (1.6 + (Get-Random -Minimum 0 -Maximum 22) / 10.0) / $speed
    $sway = New-Object System.Windows.Media.Animation.DoubleAnimation (-$amp), $amp, ([System.Windows.Duration][TimeSpan]::FromSeconds($sdur))
    $sway.AutoReverse = $true; $sway.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $sway)

    $fdur = (0.5 + (Get-Random -Minimum 0 -Maximum 12) / 10.0) / $speed
    $fl = New-Object System.Windows.Media.Animation.DoubleAnimation 0.5, 1.4, ([System.Windows.Duration][TimeSpan]::FromSeconds($fdur))
    $fl.AutoReverse = $true; $fl.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $fl)
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $fl)
  }
}

# Warm heat haze from the bottom edge: a transparent->orange vertical wash plus a few
# drifting radial blooms low in the card. Mirrors the ocean sea + sakura bloom.
function Add-DragonGlow($canvas, [double]$w, [double]$h, [double]$speed) {
  $base = New-Object System.Windows.Shapes.Rectangle
  $base.Width = $w; $base.Height = $h
  $lg = New-Object System.Windows.Media.LinearGradientBrush
  $lg.StartPoint = '0,0'; $lg.EndPoint = '0,1'
  $lg.GradientStops.Add((New-DragonStop '#F97316' 0.0 0.0))
  $lg.GradientStops.Add((New-DragonStop '#EA580C' 0.10 0.55))
  $lg.GradientStops.Add((New-DragonStop '#DC2626' 0.34 1.0))
  $base.Fill = $lg
  [System.Windows.Controls.Canvas]::SetLeft($base, 0); [System.Windows.Controls.Canvas]::SetTop($base, 0)
  $canvas.Children.Add($base) | Out-Null

  foreach ($b in @(
      @{ cx = ($w * 0.30); r = ($h * 0.70); col = '#F97316'; op = 0.22; dur = 22 },
      @{ cx = ($w * 0.70); r = ($h * 0.85); col = '#DC2626'; op = 0.18; dur = 28 })) {
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $b.r * 2; $e.Height = $b.r * 2
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-DragonStop $b.col $b.op 0.0))
    $rg.GradientStops.Add((New-DragonStop $b.col ($b.op * 0.4) 0.5))
    $rg.GradientStops.Add((New-DragonStop $b.col 0.0 1.0))
    $e.Fill = $rg
    [System.Windows.Controls.Canvas]::SetLeft($e, $b.cx - $b.r); [System.Windows.Controls.Canvas]::SetTop($e, $h - $b.r)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $e.RenderTransform = $tt
    $canvas.Children.Add($e) | Out-Null
    $dx = New-Object System.Windows.Media.Animation.DoubleAnimation 0, ($w * 0.06), ([System.Windows.Duration][TimeSpan]::FromSeconds($b.dur / $speed))
    $dx.AutoReverse = $true; $dx.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $dx)
  }
}

# Molten lava pool along the bottom: layered glowing sine surfaces (reusing the ocean
# wave geometry, dot-sourced alongside this file) scrolling sideways, each filled with
# a vertical lava gradient (bright at the surface, deep red below). Bright crack
# hotspots sit on the surface and pulse via a ScaleTransform (the twinkle trick).
function Add-DragonLava($canvas, [double]$w, [double]$h, [double]$speed) {
  $layers = @(
    @{ amp = 5; period = ($w * 0.85); top = ($h * 0.86); dur = 14; surface = '#F97316'; deep = '#7F1D1D'; op = 0.85 },
    @{ amp = 4; period = ($w * 0.55); top = ($h * 0.93); dur = 10; surface = '#FDE047'; deep = '#B91C1C'; op = 1.0 }
  )
  foreach ($L in $layers) {
    $pathW = $w + $L.period   # one extra period so the -period scroll never reveals an edge
    $data = New-WavePathData $pathW $L.period $L.amp $L.top $h ([Math]::Max(4.0, $L.period / 24.0))
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($data)
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.StartPoint = '0,0'; $g.EndPoint = '0,1'   # surface (top of bounds) -> deep
    $g.GradientStops.Add((New-DragonStop $L.surface 1.0 0.0))
    $g.GradientStops.Add((New-DragonStop $L.surface 0.9 0.12))
    $g.GradientStops.Add((New-DragonStop $L.deep 1.0 0.6))
    $g.GradientStops.Add((New-DragonStop $L.deep 1.0 1.0))
    $path.Fill = $g
    $path.Opacity = $L.op
    [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $path.RenderTransform = $tt
    $canvas.Children.Add($path) | Out-Null
    $scroll = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-$L.period), ([System.Windows.Duration][TimeSpan]::FromSeconds($L.dur / $speed))
    $scroll.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $scroll)
  }

  # Glowing crack hotspots bobbing on the surface.
  $n = 5
  for ($i = 0; $i -lt $n; $i++) {
    $r = 8 + (Get-Random -Minimum 0 -Maximum 16)
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $r * 2; $e.Height = $r * 2
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-DragonStop '#FFF3B0' 0.85 0.0))
    $rg.GradientStops.Add((New-DragonStop '#F97316' 0.45 0.5))
    $rg.GradientStops.Add((New-DragonStop '#F97316' 0.0 1.0))
    $e.Fill = $rg
    $x = ($i + 0.5) / $n * $w - $r
    $y = $h * (0.88 + (Get-Random -Minimum 0 -Maximum 8) / 100.0) - $r
    [System.Windows.Controls.Canvas]::SetLeft($e, $x); [System.Windows.Controls.Canvas]::SetTop($e, $y)
    $sc = New-Object System.Windows.Media.ScaleTransform 1, 1
    $sc.CenterX = $r; $sc.CenterY = $r
    $e.RenderTransform = $sc
    $canvas.Children.Add($e) | Out-Null
    $pdur = (1.4 + (Get-Random -Minimum 0 -Maximum 20) / 10.0) / $speed
    $pulse = New-Object System.Windows.Media.Animation.DoubleAnimation 0.6, 1.25, ([System.Windows.Duration][TimeSpan]::FromSeconds($pdur))
    $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pulse)
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pulse)
  }
}

# A single gold coin: a flattened disc with a warm radial sheen and a darker rim.
function New-CoinVisual([double]$d) {
  $e = New-Object System.Windows.Shapes.Ellipse
  $e.Width = $d; $e.Height = $d * 0.5          # flattened, seen at an angle
  $rg = New-Object System.Windows.Media.RadialGradientBrush
  $rg.GradientOrigin = '0.35,0.3'; $rg.Center = '0.5,0.5'; $rg.RadiusX = 0.7; $rg.RadiusY = 0.7
  $rg.GradientStops.Add((New-SceneStopLocal '#FFF4C2' 0.0))
  $rg.GradientStops.Add((New-SceneStopLocal '#F5C542' 0.55))
  $rg.GradientStops.Add((New-SceneStopLocal '#B8860B' 1.0))
  $e.Fill = $rg
  $e.Stroke = New-Brush '#7A4F08'; $e.StrokeThickness = 0.6
  $e
}

# Plain (opaque) gradient stop helper for the gold visuals.
function New-SceneStopLocal([string]$hex, [double]$offset) {
  New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)), $offset
}

# A dragon's hoard that completely fills the bottom of the card: a solid gold bed
# (so no card shows through), densely tiled overlapping coins for texture, a crest of
# coins poking above the surface, coloured gems and twinkling glints. Static pile;
# only the glints animate (scale twinkle — the reliable repaint path here).
function Add-DragonTreasure($canvas, [double]$w, [double]$h, [double]$speed) {
  $pileH = $h * 0.46
  $pileTop = $h - $pileH

  # Solid gold bed across the full width: guarantees the bottom is completely filled.
  $bed = New-Object System.Windows.Shapes.Rectangle
  $bed.Width = $w; $bed.Height = $pileH + 2
  $bg = New-Object System.Windows.Media.LinearGradientBrush
  $bg.StartPoint = '0,0'; $bg.EndPoint = '0,1'
  $bg.GradientStops.Add((New-SceneStopLocal '#FFE9A8' 0.0))
  $bg.GradientStops.Add((New-SceneStopLocal '#F5C542' 0.45))
  $bg.GradientStops.Add((New-SceneStopLocal '#C8901A' 1.0))
  $bed.Fill = $bg
  [System.Windows.Controls.Canvas]::SetLeft($bed, 0); [System.Windows.Controls.Canvas]::SetTop($bed, $pileTop)
  $canvas.Children.Add($bed) | Out-Null

  # Dense coin tiling over the whole bed (crest poking a little above the surface).
  # Draw back-to-front (top rows first) so lower coins overlap on top.
  $coins = @()
  for ($y = $pileTop - 6; $y -lt $h; $y += 12) {
    for ($x = -8; $x -lt ($w + 8); $x += 15) {
      $d = 13 + (Get-Random -Minimum 0 -Maximum 10)
      $jx = $x + (Get-Random -Minimum -5 -Maximum 5)
      $jy = $y + (Get-Random -Minimum -4 -Maximum 4)
      $coins += @{ x = $jx; y = $jy; d = $d }
    }
  }
  foreach ($c in ($coins | Sort-Object { $_.y })) {
    $coin = New-CoinVisual $c.d
    [System.Windows.Controls.Canvas]::SetLeft($coin, $c.x - $c.d / 2); [System.Windows.Controls.Canvas]::SetTop($coin, $c.y)
    $canvas.Children.Add($coin) | Out-Null
  }

  # Coloured gems resting across the surface.
  $gemCols = @('#E0115F', '#10B981', '#2563EB', '#9333EA', '#22D3EE', '#F43F5E', '#34D399')
  for ($i = 0; $i -lt 7; $i++) {
    $gw = 13 + (Get-Random -Minimum 0 -Maximum 9); $gh = $gw * 0.95
    $col = $gemCols[$i % $gemCols.Count]
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = [System.Windows.Media.Geometry]::Parse((New-GemPathData $gw $gh))
    $rg = New-Object System.Windows.Media.LinearGradientBrush
    $rg.StartPoint = '0,0'; $rg.EndPoint = '0,1'
    $rg.GradientStops.Add((New-SceneStopLocal '#FFFFFF' 0.0))
    $rg.GradientStops.Add((New-SceneStopLocal $col 0.4))
    $rg.GradientStops.Add((New-SceneStopLocal $col 1.0))
    $p.Fill = $rg
    $p.Stroke = New-Brush '#FFFFFF'; $p.StrokeThickness = 0.5
    $gx = ($i + 0.5) / 7 * $w + (Get-Random -Minimum -22 -Maximum 22)
    $gy = $pileTop + (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * ($pileH * 0.5)
    [System.Windows.Controls.Canvas]::SetLeft($p, $gx); [System.Windows.Controls.Canvas]::SetTop($p, $gy)
    $canvas.Children.Add($p) | Out-Null
  }

  # Twinkling glints scattered across the hoard.
  $nGlint = 14
  for ($i = 0; $i -lt $nGlint; $i++) {
    $s = 6 + (Get-Random -Minimum 0 -Maximum 8)
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = [System.Windows.Media.Geometry]::Parse((New-GlintPathData $s))
    $p.Fill = New-Brush '#FFFDE7'
    $gx = (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $w
    $gy = $pileTop + (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $pileH
    [System.Windows.Controls.Canvas]::SetLeft($p, $gx); [System.Windows.Controls.Canvas]::SetTop($p, $gy)
    $sc = New-Object System.Windows.Media.ScaleTransform 0.3, 0.3
    $sc.CenterX = $s / 2; $sc.CenterY = $s / 2
    $p.RenderTransform = $sc
    $canvas.Children.Add($p) | Out-Null
    $tdur = (0.8 + (Get-Random -Minimum 0 -Maximum 16) / 10.0) / $speed
    $tw = New-Object System.Windows.Media.Animation.DoubleAnimation 0.2, 1.2, ([System.Windows.Duration][TimeSpan]::FromSeconds($tdur))
    $tw.AutoReverse = $true; $tw.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $tw)
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $tw)
  }
}

# Glowing coal bed: a dark mound of rounded coals along the bottom, each with a hot
# core that breathes (ScaleTransform pulse — opacity animation is unreliable here).
function Add-DragonCoals($canvas, [double]$w, [double]$h, [double]$speed) {
  $bedTop = $h * 0.78
  $bed = New-Object System.Windows.Shapes.Rectangle
  $bed.Width = $w; $bed.Height = $h - $bedTop + 2
  $bg = New-Object System.Windows.Media.LinearGradientBrush
  $bg.StartPoint = '0,0'; $bg.EndPoint = '0,1'
  $bg.GradientStops.Add((New-SceneStopLocal '#2A1A12' 0.0))
  $bg.GradientStops.Add((New-SceneStopLocal '#1A0F0A' 1.0))
  $bed.Fill = $bg
  [System.Windows.Controls.Canvas]::SetLeft($bed, 0); [System.Windows.Controls.Canvas]::SetTop($bed, $bedTop)
  $canvas.Children.Add($bed) | Out-Null

  for ($row = 0; $row -lt 2; $row++) {
    $cy = $bedTop + $row * ($h - $bedTop) * 0.45
    for ($x = -10; $x -lt ($w + 10); $x += 24) {
      $cw = 22 + (Get-Random -Minimum 0 -Maximum 18)
      $jx = $x + (Get-Random -Minimum -6 -Maximum 6)
      $jy = $cy + (Get-Random -Minimum -4 -Maximum 6)
      $coal = New-Object System.Windows.Shapes.Ellipse
      $coal.Width = $cw; $coal.Height = $cw * 0.6
      $coal.Fill = New-Brush '#1A0F0A'
      [System.Windows.Controls.Canvas]::SetLeft($coal, $jx); [System.Windows.Controls.Canvas]::SetTop($coal, $jy)
      $canvas.Children.Add($coal) | Out-Null
      # Hot glowing core.
      $core = New-Object System.Windows.Shapes.Ellipse
      $cr = $cw * 0.7
      $core.Width = $cr; $core.Height = $cr * 0.6
      $rg = New-Object System.Windows.Media.RadialGradientBrush
      $rg.GradientStops.Add((New-DragonStop '#FDE047' 0.85 0.0))
      $rg.GradientStops.Add((New-DragonStop '#F97316' 0.55 0.45))
      $rg.GradientStops.Add((New-DragonStop '#DC2626' 0.0 1.0))
      $core.Fill = $rg
      [System.Windows.Controls.Canvas]::SetLeft($core, $jx + ($cw - $cr) / 2); [System.Windows.Controls.Canvas]::SetTop($core, $jy + ($cw * 0.6 - $cr * 0.6) / 2)
      $sc = New-Object System.Windows.Media.ScaleTransform 1, 1
      $sc.CenterX = $cr / 2; $sc.CenterY = $cr * 0.3
      $core.RenderTransform = $sc
      $canvas.Children.Add($core) | Out-Null
      $pdur = (1.3 + (Get-Random -Minimum 0 -Maximum 22) / 10.0) / $speed
      $pulse = New-Object System.Windows.Media.Animation.DoubleAnimation 0.45, 1.15, ([System.Windows.Duration][TimeSpan]::FromSeconds($pdur))
      $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
      $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pulse)
      $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pulse)
    }
  }
}

# Heat shimmer: faint warm vertical hazes near the bottom that waver sideways and
# breathe, suggesting rising hot air without a structured flame shape. All motion via
# RenderTransform (X sway + ScaleY breathe).
function Add-DragonShimmer($canvas, [double]$w, [double]$h, [double]$speed) {
  $n = 7
  $bandH = $h * 0.5
  for ($i = 0; $i -lt $n; $i++) {
    $cw = $w * (0.10 + (Get-Random -Minimum 0 -Maximum 8) / 100.0)
    $r = New-Object System.Windows.Shapes.Rectangle
    $r.Width = $cw; $r.Height = $bandH
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.StartPoint = '0,0'; $g.EndPoint = '0,1'
    $g.GradientStops.Add((New-DragonStop '#F97316' 0.0 0.0))
    $g.GradientStops.Add((New-DragonStop '#F97316' 0.10 0.6))
    $g.GradientStops.Add((New-DragonStop '#FDBA74' 0.18 1.0))
    $r.Fill = $g
    $x = ($i + 0.5) / $n * $w - $cw / 2
    [System.Windows.Controls.Canvas]::SetLeft($r, $x); [System.Windows.Controls.Canvas]::SetTop($r, $h - $bandH)
    $sc = New-Object System.Windows.Media.ScaleTransform 1, 1
    $sc.CenterX = $cw / 2; $sc.CenterY = $bandH
    $tt = New-Object System.Windows.Media.TranslateTransform
    $grp = New-Object System.Windows.Media.TransformGroup
    $grp.Children.Add($sc); $grp.Children.Add($tt)
    $r.RenderTransform = $grp
    $canvas.Children.Add($r) | Out-Null
    $sdur = (2.0 + (Get-Random -Minimum 0 -Maximum 20) / 10.0) / $speed
    $amp = 6 + (Get-Random -Minimum 0 -Maximum 8)
    $sway = New-Object System.Windows.Media.Animation.DoubleAnimation (-$amp), $amp, ([System.Windows.Duration][TimeSpan]::FromSeconds($sdur))
    $sway.AutoReverse = $true; $sway.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $sway)
    $br = New-Object System.Windows.Media.Animation.DoubleAnimation 0.85, 1.15, ([System.Windows.Duration][TimeSpan]::FromSeconds($sdur * 1.3))
    $br.AutoReverse = $true; $br.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $br)
  }
}

# Dark translucent smoke wisps rising slowly and growing as they climb.
function Add-DragonSmoke($canvas, [double]$w, [double]$h, [double]$speed) {
  $n = 4
  for ($i = 0; $i -lt $n; $i++) {
    $r = $h * (0.30 + (Get-Random -Minimum 0 -Maximum 30) / 100.0)
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $r * 2; $e.Height = $r * 2
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-DragonStop '#3F3A38' 0.16 0.0))
    $rg.GradientStops.Add((New-DragonStop '#2A2624' 0.08 0.55))
    $rg.GradientStops.Add((New-DragonStop '#1A0F0A' 0.0 1.0))
    $e.Fill = $rg
    $x = (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $w - $r
    [System.Windows.Controls.Canvas]::SetLeft($e, $x); [System.Windows.Controls.Canvas]::SetTop($e, -$r)
    $sc = New-Object System.Windows.Media.ScaleTransform 0.6, 0.6
    $sc.CenterX = $r; $sc.CenterY = $r
    $tt = New-Object System.Windows.Media.TranslateTransform
    $grp = New-Object System.Windows.Media.TransformGroup
    $grp.Children.Add($sc); $grp.Children.Add($tt)
    $e.RenderTransform = $grp
    $canvas.Children.Add($e) | Out-Null

    $dur = (14.0 + (Get-Random -Minimum 0 -Maximum 80) / 10.0) / $speed
    $phase = (Get-Random -Minimum 0 -Maximum 1000) / 1000.0
    Add-VertLoop $tt ($h + $r) (-$r) $dur $phase
    $grow = New-Object System.Windows.Media.Animation.DoubleAnimation 0.5, 1.3, ([System.Windows.Duration][TimeSpan]::FromSeconds($dur))
    $grow.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $grow)
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $grow)
  }
}

# Render the dragon scene into $box.Scene. $cfg: embers (default on) / count / speed /
# glow / smoke; bottom = 'lava' | 'treasure' | 'coals' | 'shimmer' | 'none'
# (mutually-exclusive bottom layer, default 'lava'). Back (glow) to front (embers).
function Start-Dragon($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }
  $canvas.Width = $w; $canvas.Height = $h

  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }
  $count = [int]$cfg.count; if ($count -le 0) { $count = 26 }
  $bottom = [string]$cfg.bottom; if (-not $bottom) { $bottom = 'lava' }

  if ($cfg.glow)   { Add-DragonGlow $canvas $w $h $speed }
  switch ($bottom) {
    'lava'     { Add-DragonLava     $canvas $w $h $speed }
    'treasure' { Add-DragonTreasure $canvas $w $h $speed }
    'coals'    { Add-DragonCoals    $canvas $w $h $speed }
    'shimmer'  { Add-DragonShimmer  $canvas $w $h $speed }
  }
  if ($cfg.smoke)  { Add-DragonSmoke  $canvas $w $h $speed }
  if ($cfg.embers) { Add-DragonEmbers $canvas $w $h $count $speed }
}
