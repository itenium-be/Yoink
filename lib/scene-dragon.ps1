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

# A single gold coin: a rim ring + an inset face with a warm radial sheen, in one of a
# few gold tones (yellow / rose / pale). Flattened (seen at an angle). Canvas group.
function New-CoinVisual([double]$d, [string]$tone) {
  switch ($tone) {
    'rose'  { $rim = '#9C5A2E'; $hi = '#FFE0C0'; $mid = '#E8A23D'; $lo = '#B5702A' }
    'pale'  { $rim = '#9E8F50'; $hi = '#FFFBE6'; $mid = '#E9D98A'; $lo = '#B9A24E' }
    default { $rim = '#8A5E10'; $hi = '#FFF4C2'; $mid = '#F5C542'; $lo = '#C8901A' }
  }
  $g = New-Object System.Windows.Controls.Canvas
  $hh = $d * 0.52
  $rimE = New-Object System.Windows.Shapes.Ellipse
  $rimE.Width = $d; $rimE.Height = $hh; $rimE.Fill = New-Brush $rim
  $g.Children.Add($rimE) | Out-Null
  $fw = $d * 0.72; $fh = $hh * 0.72
  $face = New-Object System.Windows.Shapes.Ellipse
  $face.Width = $fw; $face.Height = $fh
  $rg = New-Object System.Windows.Media.RadialGradientBrush
  $rg.GradientOrigin = '0.35,0.3'; $rg.Center = '0.5,0.5'; $rg.RadiusX = 0.7; $rg.RadiusY = 0.7
  $rg.GradientStops.Add((New-SceneStopLocal $hi 0.0))
  $rg.GradientStops.Add((New-SceneStopLocal $mid 0.6))
  $rg.GradientStops.Add((New-SceneStopLocal $lo 1.0))
  $face.Fill = $rg
  [System.Windows.Controls.Canvas]::SetLeft($face, ($d - $fw) / 2); [System.Windows.Controls.Canvas]::SetTop($face, ($hh - $fh) / 2)
  $g.Children.Add($face) | Out-Null
  $g
}

# A gold crown (zig-zag band) of width ~$s, with little gem points. Canvas group.
function New-CrownVisual([double]$s) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $n = { param($v) ([double]$v).ToString('0.##', $ic) }
  $cw = $s; $ch = $s * 0.7
  $gold = New-Object System.Windows.Media.LinearGradientBrush
  $gold.StartPoint = '0,0'; $gold.EndPoint = '0,1'
  $gold.GradientStops.Add((New-SceneStopLocal '#FFE9A8' 0.0))
  $gold.GradientStops.Add((New-SceneStopLocal '#D9A52E' 1.0))
  $g = New-Object System.Windows.Controls.Canvas
  $band = New-Object System.Windows.Shapes.Path
  $band.Data = [System.Windows.Media.Geometry]::Parse(
    "M 0 $(& $n $ch) L 0 $(& $n ($ch*0.55)) L $(& $n ($cw*0.2)) $(& $n ($ch*0.85)) L $(& $n ($cw*0.3)) $(& $n ($ch*0.15)) L $(& $n ($cw*0.5)) $(& $n ($ch*0.7)) L $(& $n ($cw*0.7)) $(& $n ($ch*0.15)) L $(& $n ($cw*0.8)) $(& $n ($ch*0.85)) L $(& $n $cw) $(& $n ($ch*0.55)) L $(& $n $cw) $(& $n $ch) Z")
  $band.Fill = $gold; $g.Children.Add($band) | Out-Null
  foreach ($px in @(0.3, 0.5, 0.7)) {
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = $s * 0.1; $dot.Height = $s * 0.1; $dot.Fill = New-Brush '#E0115F'
    [System.Windows.Controls.Canvas]::SetLeft($dot, $cw * $px - $s * 0.05); [System.Windows.Controls.Canvas]::SetTop($dot, $ch * 0.10)
    $g.Children.Add($dot) | Out-Null
  }
  $g
}

# Plain (opaque) gradient stop helper for the gold visuals.
function New-SceneStopLocal([string]$hex, [double]$offset) {
  New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)), $offset
}

# A dragon's hoard along the bottom: a soft gold halo, a solid gold bed (so no card
# shows through), densely tiled coins in mixed gold tones/sizes, a fire-lit rim along
# the crest, a crown poking up, coloured gems, cross-flare glints and a slow
# shimmer sweep. Only the glints + shimmer animate (transform-driven, the reliable path).
function Add-DragonTreasure($canvas, [double]$w, [double]$h, [double]$speed) {
  $pileH = $h * 0.12
  $pileTop = $h - $pileH

  # Soft gold halo glowing above the pile (depth).
  $halo = New-Object System.Windows.Shapes.Ellipse
  $halo.Width = $w * 1.1; $halo.Height = $pileH * 5
  $hg = New-Object System.Windows.Media.RadialGradientBrush
  $hg.GradientStops.Add((New-DragonStop '#F5C542' 0.22 0.0))
  $hg.GradientStops.Add((New-DragonStop '#F5C542' 0.06 0.55))
  $hg.GradientStops.Add((New-DragonStop '#F5C542' 0.0 1.0))
  $halo.Fill = $hg
  [System.Windows.Controls.Canvas]::SetLeft($halo, -$w * 0.05); [System.Windows.Controls.Canvas]::SetTop($halo, $h - $pileH * 3.4)
  $canvas.Children.Add($halo) | Out-Null

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

  # Dense coins in mixed tones/sizes; occasional bigger doubloons. Back-to-front by y.
  $tones = @('yellow', 'yellow', 'yellow', 'rose', 'pale')
  $coins = @()
  for ($y = $pileTop - 6; $y -lt $h; $y += 11) {
    for ($x = -8; $x -lt ($w + 8); $x += 14) {
      $d = if ((Get-Random -Minimum 0 -Maximum 10) -lt 2) { 22 + (Get-Random -Minimum 0 -Maximum 10) } else { 12 + (Get-Random -Minimum 0 -Maximum 9) }
      $jx = $x + (Get-Random -Minimum -5 -Maximum 5)
      $jy = $y + (Get-Random -Minimum -4 -Maximum 4)
      $coins += @{ x = $jx; y = $jy; d = $d; tone = $tones[(Get-Random -Minimum 0 -Maximum $tones.Count)] }
    }
  }
  foreach ($c in ($coins | Sort-Object { $_.y })) {
    $coin = New-CoinVisual $c.d $c.tone
    [System.Windows.Controls.Canvas]::SetLeft($coin, $c.x - $c.d / 2); [System.Windows.Controls.Canvas]::SetTop($coin, $c.y)
    $canvas.Children.Add($coin) | Out-Null
  }

  # Fire-lit rim along the crest of the pile (top coins catch the light).
  $rim = New-Object System.Windows.Shapes.Rectangle
  $rim.Width = $w; $rim.Height = $pileH * 0.7
  $rg2 = New-Object System.Windows.Media.LinearGradientBrush
  $rg2.StartPoint = '0,0'; $rg2.EndPoint = '0,1'
  $rg2.GradientStops.Add((New-DragonStop '#FFF4C2' 0.55 0.0))
  $rg2.GradientStops.Add((New-DragonStop '#FFF4C2' 0.0 1.0))
  $rim.Fill = $rg2
  [System.Windows.Controls.Canvas]::SetLeft($rim, 0); [System.Windows.Controls.Canvas]::SetTop($rim, $pileTop - 3)
  $canvas.Children.Add($rim) | Out-Null

  # A crown poking up out of the hoard.
  $crown = New-CrownVisual ($pileH * 1.6)
  [System.Windows.Controls.Canvas]::SetLeft($crown, $w * 0.62); [System.Windows.Controls.Canvas]::SetTop($crown, $pileTop - $pileH * 0.9)
  $canvas.Children.Add($crown) | Out-Null

  # Coloured gems resting across the surface.
  $gemCols = @('#E0115F', '#10B981', '#2563EB', '#9333EA', '#22D3EE', '#F43F5E', '#34D399')
  for ($i = 0; $i -lt 7; $i++) {
    $gw = 12 + (Get-Random -Minimum 0 -Maximum 9); $gh = $gw * 0.95
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

  # Bright cross-flare glints (fewer, bigger) twinkling on the gold.
  for ($i = 0; $i -lt 8; $i++) {
    $s = 9 + (Get-Random -Minimum 0 -Maximum 9)
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = [System.Windows.Media.Geometry]::Parse((New-GlintPathData $s))
    $p.Fill = New-Brush '#FFFFFF'
    $gx = (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $w
    $gy = $pileTop + (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $pileH
    [System.Windows.Controls.Canvas]::SetLeft($p, $gx); [System.Windows.Controls.Canvas]::SetTop($p, $gy)
    $sc = New-Object System.Windows.Media.ScaleTransform 0.2, 0.2
    $sc.CenterX = $s / 2; $sc.CenterY = $s / 2
    $p.RenderTransform = $sc
    $canvas.Children.Add($p) | Out-Null
    $tdur = (0.8 + (Get-Random -Minimum 0 -Maximum 16) / 10.0) / $speed
    $tw = New-Object System.Windows.Media.Animation.DoubleAnimation 0.15, 1.3, ([System.Windows.Duration][TimeSpan]::FromSeconds($tdur))
    $tw.AutoReverse = $true; $tw.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $tw)
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $tw)
  }

  # Slow shimmer sweep: a soft bright diagonal stripe travelling across the gold.
  $sweep = New-Object System.Windows.Shapes.Rectangle
  $sweep.Width = $w * 0.22; $sweep.Height = $pileH * 2.4
  $sg = New-Object System.Windows.Media.LinearGradientBrush
  $sg.StartPoint = '0,0'; $sg.EndPoint = '1,0'
  $sg.GradientStops.Add((New-DragonStop '#FFFFFF' 0.0 0.0))
  $sg.GradientStops.Add((New-DragonStop '#FFFFFF' 0.18 0.5))
  $sg.GradientStops.Add((New-DragonStop '#FFFFFF' 0.0 1.0))
  $sweep.Fill = $sg
  [System.Windows.Controls.Canvas]::SetTop($sweep, $pileTop - $pileH * 1.0)
  $rot = New-Object System.Windows.Media.RotateTransform 14
  $tt = New-Object System.Windows.Media.TranslateTransform
  $grp = New-Object System.Windows.Media.TransformGroup
  $grp.Children.Add($rot); $grp.Children.Add($tt)
  $sweep.RenderTransform = $grp
  $canvas.Children.Add($sweep) | Out-Null
  $sweepA = New-Object System.Windows.Media.Animation.DoubleAnimation (-$w * 0.3), ($w * 1.3), ([System.Windows.Duration][TimeSpan]::FromSeconds(7.0 / $speed))
  $sweepA.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $sweepA)
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

# A distant volcano backdrop, offset to the left: a dark-brown mountain cone with a
# crater and a few ejected sparks. Drawn behind everything as a background. Motion is
# transform-driven (rise/sway).
function Add-DragonVolcano($canvas, [double]$w, [double]$h, [double]$speed) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $n = { param($v) ([double]$v).ToString('0.##', $ic) }
  $px = $w * 0.18                 # peak centre (offset well to the left)
  $py = $h * 0.34                 # peak height
  $baseHalf = $w * 0.27
  $craterHalf = $w * 0.055
  $craterFloor = $py + $h * 0.05

  # Dark cone silhouette with a crater notch.
  $cone = New-Object System.Windows.Shapes.Path
  $cone.Data = [System.Windows.Media.Geometry]::Parse(
    "M $(& $n ($px-$baseHalf)) $(& $n $h) " +
    "L $(& $n ($px-$craterHalf)) $(& $n $py) " +
    "L $(& $n ($px-$craterHalf*0.4)) $(& $n $craterFloor) " +
    "L $(& $n ($px+$craterHalf*0.4)) $(& $n $craterFloor) " +
    "L $(& $n ($px+$craterHalf)) $(& $n $py) " +
    "L $(& $n ($px+$baseHalf)) $(& $n $h) Z")
  # Flat, fully-opaque very-dark brown (an ominous mountain); a lit rim keeps the
  # silhouette readable against the near-black card.
  $cone.Fill = New-Brush '#140800'
  $cone.Stroke = New-Brush '#33200F'; $cone.StrokeThickness = 1.0   # subtle dark edge, just lifts it off the card
  $canvas.Children.Add($cone) | Out-Null

  # Small confined glow in the crater notch (origin for the sparks); kept tight so it
  # does not spill down and wash out the cone.
  $src = New-Object System.Windows.Shapes.Ellipse
  $sr = $craterHalf * 0.7
  $src.Width = $sr * 2; $src.Height = $sr
  $srg = New-Object System.Windows.Media.RadialGradientBrush
  $srg.GradientStops.Add((New-DragonStop '#FFF3B0' 0.6 0.0))
  $srg.GradientStops.Add((New-DragonStop '#F97316' 0.25 0.55))
  $srg.GradientStops.Add((New-DragonStop '#F97316' 0.0 1.0))
  $src.Fill = $srg
  [System.Windows.Controls.Canvas]::SetLeft($src, $px - $sr); [System.Windows.Controls.Canvas]::SetTop($src, $craterFloor - $sr * 0.5)
  $canvas.Children.Add($src) | Out-Null

  # A few sparks ejected upward from the crater, fanning out.
  for ($i = 0; $i -lt 6; $i++) {
    $sz = 2.0 + (Get-Random -Minimum 0 -Maximum 20) / 10.0
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $sz; $e.Height = $sz
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-DragonStop '#FDE047' 1.0 0.0))
    $rg.GradientStops.Add((New-DragonStop '#F97316' 0.5 0.6))
    $rg.GradientStops.Add((New-DragonStop '#F97316' 0.0 1.0))
    $e.Fill = $rg
    [System.Windows.Controls.Canvas]::SetLeft($e, $px - $sz / 2); [System.Windows.Controls.Canvas]::SetTop($e, 0)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $e.RenderTransform = $tt
    $canvas.Children.Add($e) | Out-Null
    $dur = (2.5 + (Get-Random -Minimum 0 -Maximum 30) / 10.0) / $speed
    Add-VertLoop $tt $craterFloor ($py - $h * 0.18) $dur ((Get-Random -Minimum 0 -Maximum 1000) / 1000.0)
    $fan = $craterHalf * ((Get-Random -Minimum -20 -Maximum 20) / 10.0)
    $sway = New-Object System.Windows.Media.Animation.DoubleAnimation 0, $fan, ([System.Windows.Duration][TimeSpan]::FromSeconds($dur))
    $sway.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $sway)
  }
}

# Render the dragon scene into $box.Scene. $cfg: embers (default on) / count / speed /
# glow / smoke / volcano; bottom = 'lava' | 'treasure' | 'none'
# (mutually-exclusive bottom layer, default 'lava'). Back (volcano) to front (embers).
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
  if ($cfg.volcano) { Add-DragonVolcano $canvas $w $h $speed }   # in front of the glow wash so it reads solid
  switch ($bottom) {
    'lava'     { Add-DragonLava     $canvas $w $h $speed }
    'treasure' { Add-DragonTreasure $canvas $w $h $speed }
  }
  if ($cfg.smoke)  { Add-DragonSmoke  $canvas $w $h $speed }
  if ($cfg.embers) { Add-DragonEmbers $canvas $w $h $count $speed }
}
