# Scenery renderer: robot — a full-card circuit-board mesh (dim steel-teal traces +
# solder pads) with bright-cyan pulses travelling along the traces, blinking status
# LEDs and broadcast signal rings, over a soft cyan glow wash. New-TracePathData /
# New-RobotStop are the pure bits (unit-tested); the Add-Robot* helpers and Start-Robot
# build live WPF visuals. Dot-sourced by show-notification.ps1; New-Brush comes from
# notification-box.ps1.

# A right-angle (Manhattan) circuit trace as an OPEN XAML polyline from an ordered
# point list (each point @(x,y)). Coordinates are SPACE-separated and formatted with
# the invariant culture — the nl-BE machine locale would emit ',' decimals and
# Geometry.Parse would choke (see scene-dragon's New-WavePathData note).
function New-TracePathData($points) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $n = { param($v) ([double]$v).ToString('0.##', $ic) }
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $points.Count; $i++) {
    $pt = $points[$i]
    $cmd = if ($i -eq 0) { 'M' } else { 'L' }
    [void]$sb.Append("$cmd $(& $n $pt[0]) $(& $n $pt[1]) ")
  }
  $sb.ToString().TrimEnd()
}

# Gradient stop with a 0..1 alpha baked into #AARRGGBB (lets the glow/pulse/ring
# gradients fade to transparent without a separate Opacity per stop). Mirrors
# New-DragonStop / New-SpaceStop.
function New-RobotStop([string]$hex6, [double]$alpha, [double]$offset) {
  $a = [int][Math]::Round(255 * $alpha)
  $argb = ('#{0:X2}{1}' -f $a, $hex6.TrimStart('#'))
  New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($argb)), $offset
}

# A seamless 0..1 loop on a single Double property from $from to $to, started mid-cycle
# at $phase to scatter without a negative BeginTime (unreliable here — see scene-dragon
# Add-VertLoop). The wrap is a discrete jump back to $from. Used for the ring
# grow/fade so multiple rings of one emitter desync.
function New-RobotPhasedKF([double]$dur, [double]$phase, [double]$from, [double]$to) {
  $span = $to - $from
  $startV = $from + $phase * $span
  $t1 = $dur * (1 - $phase)
  $kf = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
  $kf.Duration = [System.Windows.Duration][TimeSpan]::FromSeconds($dur)
  $kf.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $kf.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $startV, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds(0)))) | Out-Null
  $kf.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $to, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($t1)))) | Out-Null
  $kf.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteDoubleKeyFrame $from, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($t1)))) | Out-Null
  $kf.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $startV, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($dur)))) | Out-Null
  $kf
}

# Soft cyan depth: a couple of low-opacity radial blooms drifting slowly. No solid base
# wash — the card is already near-black and a flat fill would mute the traces. Mirrors
# Add-SpaceNebula / Add-DragonGlow.
function Add-RobotGlow($canvas, [double]$w, [double]$h, [double]$speed) {
  foreach ($b in @(
      @{ cx = ($w * 0.30); cy = ($h * 0.45); r = ($h * 0.78); col = '#0EA5E9'; op = 0.12; dur = 24 },
      @{ cx = ($w * 0.74); cy = ($h * 0.32); r = ($h * 0.90); col = '#22D3EE'; op = 0.10; dur = 30 })) {
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $b.r * 2; $e.Height = $b.r * 2
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-RobotStop $b.col $b.op 0.0))
    $rg.GradientStops.Add((New-RobotStop $b.col ($b.op * 0.4) 0.5))
    $rg.GradientStops.Add((New-RobotStop $b.col 0.0 1.0))
    $e.Fill = $rg
    [System.Windows.Controls.Canvas]::SetLeft($e, $b.cx - $b.r); [System.Windows.Controls.Canvas]::SetTop($e, $b.cy - $b.r)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $e.RenderTransform = $tt
    $canvas.Children.Add($e) | Out-Null
    $dx = New-Object System.Windows.Media.Animation.DoubleAnimation 0, ($w * 0.05), ([System.Windows.Duration][TimeSpan]::FromSeconds($b.dur / $speed))
    $dx.AutoReverse = $true; $dx.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $dx)
  }
}

# A grid-snapped random walk producing a right-angle "wire": horizontal mode runs
# left->right with occasional vertical jogs (vertical mode runs top->bottom). Returns
# the ordered point list for New-TracePathData.
function New-RobotWirePoints([double]$w, [double]$h, [double]$gx, [double]$gy, [int]$cols, [int]$rows, [bool]$horizontal) {
  # ArrayList so each point (a 2-element array) is added as ONE element; the `$x += ,@()`
  # idiom mis-parses the nested-array append here. Coordinates are precomputed into
  # scalar temps — `@($c * $gx, 0.0)` inline trips an op_Multiply parser quirk.
  $pts = New-Object System.Collections.ArrayList
  $add = { param($px, $py) [void]$pts.Add(@([double]$px, [double]$py)) }
  if ($horizontal) {
    $r = Get-Random -Minimum 0 -Maximum ($rows + 1)
    $c = 0
    & $add 0.0 ($r * $gy)
    while ($c -lt $cols) {
      $c = [Math]::Min($cols, $c + 2 + (Get-Random -Minimum 0 -Maximum 3))
      & $add ($c * $gx) ($r * $gy)
      if ($c -lt $cols -and (Get-Random -Minimum 0 -Maximum 10) -lt 6) {
        $dr = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { -1 } else { 1 }
        $r = [Math]::Max(0, [Math]::Min($rows, $r + $dr * (1 + (Get-Random -Minimum 0 -Maximum 2))))
        & $add ($c * $gx) ($r * $gy)
      }
    }
    & $add $w ($r * $gy)
  }
  else {
    $c = Get-Random -Minimum 1 -Maximum $cols
    $rr = 0
    & $add ($c * $gx) 0.0
    while ($rr -lt $rows) {
      $rr = [Math]::Min($rows, $rr + 2 + (Get-Random -Minimum 0 -Maximum 2))
      & $add ($c * $gx) ($rr * $gy)
      if ($rr -lt $rows -and (Get-Random -Minimum 0 -Maximum 10) -lt 5) {
        $dc = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { -1 } else { 1 }
        $c = [Math]::Max(0, [Math]::Min($cols, $c + $dc * (1 + (Get-Random -Minimum 0 -Maximum 2))))
        & $add ($c * $gx) ($rr * $gy)
      }
    }
    & $add ($c * $gx) $h
  }
  , $pts.ToArray()
}

# Full-card PCB mesh: dim steel-teal right-angle traces with solder pads at vertices,
# then bright-cyan pulses travelling ALONG the traces. The pulses ride a
# MatrixAnimationUsingPath (transform-driven, so it repaints reliably — a plain Opacity
# animation would not; see the scene-dragon pitfalls).
function Add-RobotCircuit($canvas, [double]$w, [double]$h, [double]$speed, [int]$pulseCount) {
  $gx = 28.0; $gy = 24.0
  $cols = [int][Math]::Floor($w / $gx)
  $rows = [int][Math]::Floor($h / $gy)
  $traceBrush = New-Brush '#1E3A4A'
  $padBrush = New-Brush '#2B5468'

  $wires = @()
  for ($k = 0; $k -lt 9; $k++) { $wires += @{ points = (New-RobotWirePoints $w $h $gx $gy $cols $rows $true) } }
  for ($k = 0; $k -lt 5; $k++) { $wires += @{ points = (New-RobotWirePoints $w $h $gx $gy $cols $rows $false) } }

  foreach ($wire in $wires) {
    $wire.data = New-TracePathData $wire.points
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($wire.data)
    $path.Stroke = $traceBrush; $path.StrokeThickness = 1.3; $path.StrokeLineJoin = 'Round'
    [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
    $canvas.Children.Add($path) | Out-Null
    foreach ($pt in $wire.points) {
      if ((Get-Random -Minimum 0 -Maximum 10) -lt 4) {
        $pad = New-Object System.Windows.Shapes.Ellipse
        $pd = 3.2; $pad.Width = $pd; $pad.Height = $pd; $pad.Fill = $padBrush
        [System.Windows.Controls.Canvas]::SetLeft($pad, $pt[0] - $pd / 2); [System.Windows.Controls.Canvas]::SetTop($pad, $pt[1] - $pd / 2)
        $canvas.Children.Add($pad) | Out-Null
      }
    }
  }

  for ($i = 0; $i -lt $pulseCount; $i++) {
    $wire = $wires[(Get-Random -Minimum 0 -Maximum $wires.Count)]
    $pg = [System.Windows.Media.PathGeometry]::CreateFromGeometry([System.Windows.Media.Geometry]::Parse($wire.data))
    $ps = 6.0
    $pulse = New-Object System.Windows.Shapes.Ellipse
    $pulse.Width = $ps; $pulse.Height = $ps
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-RobotStop '#FFFFFF' 1.0 0.0))
    $rg.GradientStops.Add((New-RobotStop '#22D3EE' 0.9 0.4))
    $rg.GradientStops.Add((New-RobotStop '#22D3EE' 0.0 1.0))
    $pulse.Fill = $rg
    # SetLeft/-Top centre the dot on (0,0); the path animation then translates that
    # origin onto each point of the trace.
    [System.Windows.Controls.Canvas]::SetLeft($pulse, -$ps / 2); [System.Windows.Controls.Canvas]::SetTop($pulse, -$ps / 2)
    $mt = New-Object System.Windows.Media.MatrixTransform
    $pulse.RenderTransform = $mt
    $canvas.Children.Add($pulse) | Out-Null
    $anim = New-Object System.Windows.Media.Animation.MatrixAnimationUsingPath
    $anim.PathGeometry = $pg; $anim.DoesRotateWithTangent = $false
    $dur = (3.5 + (Get-Random -Minimum 0 -Maximum 40) / 10.0) / $speed
    $anim.Duration = [System.Windows.Duration][TimeSpan]::FromSeconds($dur)
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $mt.BeginAnimation([System.Windows.Media.MatrixTransform]::MatrixProperty, $anim)
  }
}

# Broadcast signal rings expanding from a node: each ring grows (ScaleTransform) and
# fades (Opacity rides along — the concurrent scale animation drives the repaint).
# Rings of one emitter are phase-scattered so they pulse in a staggered procession.
function Add-RobotRings($canvas, [double]$w, [double]$h, [double]$speed) {
  foreach ($em in @(
      @{ cx = ($w * 0.84); cy = ($h * 0.26); max = ($h * 0.50) },
      @{ cx = ($w * 0.16); cy = ($h * 0.74); max = ($h * 0.42) })) {
    $node = New-Object System.Windows.Shapes.Ellipse
    $nd = 5.0; $node.Width = $nd; $node.Height = $nd; $node.Fill = New-Brush '#38BDF8'
    [System.Windows.Controls.Canvas]::SetLeft($node, $em.cx - $nd / 2); [System.Windows.Controls.Canvas]::SetTop($node, $em.cy - $nd / 2)
    $canvas.Children.Add($node) | Out-Null
    $ringN = 3
    for ($i = 0; $i -lt $ringN; $i++) {
      $maxR = $em.max
      $ring = New-Object System.Windows.Shapes.Ellipse
      $ring.Width = $maxR * 2; $ring.Height = $maxR * 2
      $ring.Stroke = New-Brush '#38BDF8'; $ring.StrokeThickness = 1.4
      [System.Windows.Controls.Canvas]::SetLeft($ring, $em.cx - $maxR); [System.Windows.Controls.Canvas]::SetTop($ring, $em.cy - $maxR)
      $sc = New-Object System.Windows.Media.ScaleTransform 0.1, 0.1
      $sc.CenterX = $maxR; $sc.CenterY = $maxR
      $ring.RenderTransform = $sc
      $canvas.Children.Add($ring) | Out-Null
      $dur = 4.0 / $speed
      $phase = $i / [double]$ringN
      $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, (New-RobotPhasedKF $dur $phase 0.1 1.0))
      $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, (New-RobotPhasedKF $dur $phase 0.1 1.0))
      $ring.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-RobotPhasedKF $dur $phase 0.85 0.0))
    }
  }
}

# Blinking status LEDs scattered across the board: green / amber / red / cyan indicator
# dots with a hot white core. Most blink via a ScaleTransform pulse (the twinkle trick —
# a plain Opacity animation does not repaint reliably for scene children); a few sit
# steady-on.
function Add-RobotLeds($canvas, [double]$w, [double]$h, [int]$count, [double]$speed) {
  $cols = @('#22C55E', '#F59E0B', '#EF4444', '#38BDF8')
  for ($i = 0; $i -lt $count; $i++) {
    $col = $cols[(Get-Random -Minimum 0 -Maximum $cols.Count)]
    $r = 2.5 + (Get-Random -Minimum 0 -Maximum 20) / 10.0
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $r * 2; $e.Height = $r * 2
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-RobotStop '#FFFFFF' 0.9 0.0))
    $rg.GradientStops.Add((New-RobotStop $col 0.95 0.45))
    $rg.GradientStops.Add((New-RobotStop $col 0.0 1.0))
    $e.Fill = $rg
    $x = (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $w
    $y = (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * $h
    [System.Windows.Controls.Canvas]::SetLeft($e, $x - $r); [System.Windows.Controls.Canvas]::SetTop($e, $y - $r)
    $sc = New-Object System.Windows.Media.ScaleTransform 1, 1
    $sc.CenterX = $r; $sc.CenterY = $r
    $e.RenderTransform = $sc
    $canvas.Children.Add($e) | Out-Null
    if ((Get-Random -Minimum 0 -Maximum 10) -lt 7) {
      $bdur = (0.5 + (Get-Random -Minimum 0 -Maximum 22) / 10.0) / $speed
      $pulse = New-Object System.Windows.Media.Animation.DoubleAnimation 0.35, 1.35, ([System.Windows.Duration][TimeSpan]::FromSeconds($bdur))
      $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
      $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pulse)
      $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pulse)
    }
  }
}

# Render the robot scene into $box.Scene. $cfg: glow (default on) / leds / rings / speed
# / count (LED count); base = 'circuit' | 'none' (mutually-exclusive base layer, default
# 'circuit'). Back (glow) to front (leds) draw order.
function Start-Robot($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }
  $canvas.Width = $w; $canvas.Height = $h

  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }
  $count = [int]$cfg.count; if ($count -le 0) { $count = 10 }
  $base = [string]$cfg.base; if (-not $base) { $base = 'circuit' }

  if ($cfg.glow) { Add-RobotGlow $canvas $w $h $speed }
  switch ($base) {
    'circuit' { Add-RobotCircuit $canvas $w $h $speed ([int][Math]::Max(4, $count * 0.8)) }
  }
  if ($cfg.rings) { Add-RobotRings $canvas $w $h $speed }
  if ($cfg.leds)  { Add-RobotLeds  $canvas $w $h $count $speed }
}
