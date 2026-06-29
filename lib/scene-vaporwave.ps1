# Scenery renderer: vaporwave — eight independent, flag-toggled 80s/outrun layers.
# New-GridPathData / New-MountainPathData are WPF-free + unit-tested; the Add-Vaporwave*
# helpers (added in later tasks) build live WPF visuals. Dot-sourced by show-notification.ps1.

# XAML path geometry for a receding perspective grid: `cols`+1 vertical threads
# fanning from the vanishing point (vanishX, horizonY) to evenly-spaced points along
# the bottom edge, plus `rows` full-width horizontal threads whose spacing tightens
# toward the horizon (y = horizonY + (bottomY-horizonY) * (r/rows)^2); pass rows = 0
# for vertical rays only (the live grid animates its own horizontals). One combined
# Path data string (multiple M subpaths), stroked.
# Invariant culture: XAML needs '.' decimals; nl-BE would emit ',' and choke Parse.
function New-GridPathData([double]$w, [double]$horizonY, [double]$bottomY, [int]$cols, [int]$rows, [double]$vanishX) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  if ($cols -lt 1) { $cols = 1 }
  if ($rows -lt 0) { $rows = 0 }   # rows = 0 -> vertical rays only, no horizontal threads
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  $sb = New-Object System.Text.StringBuilder
  for ($c = 0; $c -le $cols; $c++) {
    $bx = $w * $c / $cols
    [void]$sb.Append(("M {0},{1} L {2},{3} " -f (&$f $vanishX), (&$f $horizonY), (&$f $bx), (&$f $bottomY)))
  }
  for ($r = 1; $r -le $rows; $r++) {
    $t = $r / $rows
    $y = $horizonY + ($bottomY - $horizonY) * $t * $t
    [void]$sb.Append(("M 0,{0} L {1},{0} " -f (&$f $y), (&$f $w)))
  }
  $sb.ToString().TrimEnd()
}

# Filled, closed mountain-ridge silhouette: a flat baseline jagged up into `peaks`
# triangular peaks. M at the left base, then for each peak an apex (peakY) at its
# centre and a valley (baseY) at its right edge; the last valley lands at the right
# base, so Z closes the baseline.
function New-MountainPathData([double]$w, [double]$baseY, [double]$peakY, [int]$peaks) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  if ($peaks -lt 1) { $peaks = 1 }
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append(("M 0,{0} " -f (&$f $baseY)))
  for ($p = 0; $p -lt $peaks; $p++) {
    $apexX = $w * ($p + 0.5) / $peaks
    $valleyX = $w * ($p + 1) / $peaks
    [void]$sb.Append(("L {0},{1} L {2},{3} " -f (&$f $apexX), (&$f $peakY), (&$f $valleyX), (&$f $baseY)))
  }
  # The final loop valley already lands at (w, baseY); Z closes the baseline back to (0, baseY).
  [void]$sb.Append("Z")
  $sb.ToString()
}

# --- layers (back to front) --------------------------------------------------

# Sunset sky wash: a translucent pink -> purple -> cyan vertical gradient backdrop,
# kept semi-transparent so the dark card and centred text stay legible.
function Add-VaporwaveHaze($canvas, [double]$w, [double]$h) {
  $r = New-Object System.Windows.Shapes.Rectangle
  $r.Width = $w; $r.Height = $h
  $g = New-Object System.Windows.Media.LinearGradientBrush
  $g.StartPoint = '0,0'; $g.EndPoint = '0,1'
  $g.GradientStops.Add((New-SceneStop '#CCFF6AD5' 0.0))
  $g.GradientStops.Add((New-SceneStop '#99C774E8' 0.4))
  $g.GradientStops.Add((New-SceneStop '#66AD8CFF' 0.7))
  $g.GradientStops.Add((New-SceneStop '#6694D0FF' 1.0))
  $r.Fill = $g
  [System.Windows.Controls.Canvas]::SetLeft($r, 0); [System.Windows.Controls.Canvas]::SetTop($r, 0)
  $canvas.Children.Add($r) | Out-Null
}

# Banded retro sun sitting on the horizon: a circle (clipped Canvas) filled solid
# across its upper 55%, then sliced into horizontal bands that thin and spread apart
# toward the bottom (the gaps reveal the haze behind). Colour ramps yellow -> pink ->
# magenta down the disc. Gentle opacity pulse, like Add-OceanSun.
function Add-VaporwaveSun($canvas, [double]$w, [double]$h, [double]$speed) {
  $d = $h * 0.5
  $horizon = $h * 0.52
  $cx = $w * 0.5
  $sun = New-Object System.Windows.Controls.Canvas
  $sun.Width = $d; $sun.Height = $d
  $clip = New-Object System.Windows.Media.EllipseGeometry
  $clip.Center = New-Object System.Windows.Point ($d / 2), ($d / 2)
  $clip.RadiusX = $d / 2; $clip.RadiusY = $d / 2
  $sun.Clip = $clip
  # Sample the yellow -> pink -> magenta ramp as a solid colour at fraction t (0..1).
  $col = {
    param([double]$t)
    $yellow = @(255, 251, 150); $pink = @(255, 106, 213); $magenta = @(255, 113, 206)
    if ($t -le 0.5) { $lo = $yellow; $hi = $pink; $u = $t / 0.5 } else { $lo = $pink; $hi = $magenta; $u = ($t - 0.5) / 0.5 }
    $rr = [int]($lo[0] + ($hi[0] - $lo[0]) * $u)
    $gg = [int]($lo[1] + ($hi[1] - $lo[1]) * $u)
    $bb = [int]($lo[2] + ($hi[2] - $lo[2]) * $u)
    New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb($rr, $gg, $bb))
  }
  $solidH = $d * 0.55
  $top = New-Object System.Windows.Shapes.Rectangle
  $top.Width = $d; $top.Height = $solidH; $top.Fill = (& $col 0.28)
  [System.Windows.Controls.Canvas]::SetTop($top, 0)
  $sun.Children.Add($top) | Out-Null
  # Lower 45% is sliced into bands; height shrinks and the gap grows downward for the retro look.
  $y = $solidH; $bh = $d * 0.07; $gap = $d * 0.02
  while ($y -lt $d) {
    $bar = New-Object System.Windows.Shapes.Rectangle
    $bar.Width = $d; $bar.Height = $bh; $bar.Fill = (& $col ($y / $d))
    [System.Windows.Controls.Canvas]::SetTop($bar, $y)
    $sun.Children.Add($bar) | Out-Null
    $y += $bh + $gap
    $bh = [Math]::Max(1.5, $bh - $d * 0.008)
    $gap += $d * 0.006
  }
  [System.Windows.Controls.Canvas]::SetLeft($sun, $cx - $d / 2)
  [System.Windows.Controls.Canvas]::SetTop($sun, $horizon - $d)
  $canvas.Children.Add($sun) | Out-Null
  $pulse = New-Object System.Windows.Media.Animation.DoubleAnimation 0.8, 0.97, ([System.Windows.Duration][TimeSpan]::FromSeconds(5.0 / $speed))
  $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $sun.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $pulse)
}

# Twinkling dots confined to the upper sky (above the horizon band).
function Add-VaporwaveStars($canvas, [double]$w, [double]$h, [double]$speed) {
  $skyH = [int]($h * 0.48)
  for ($i = 0; $i -lt 28; $i++) {
    $sz = 1.2 + (Get-Random -Minimum 0 -Maximum 18) / 10.0
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $sz; $e.Height = $sz; $e.Fill = New-Brush '#FFFFFFFF'
    [System.Windows.Controls.Canvas]::SetLeft($e, (Get-Random -Minimum 0 -Maximum ([int]$w)))
    [System.Windows.Controls.Canvas]::SetTop($e, (Get-Random -Minimum 0 -Maximum $skyH))
    $canvas.Children.Add($e) | Out-Null
    $dur = (1.6 + (Get-Random -Minimum 0 -Maximum 30) / 10.0) / $speed
    Add-Twinkle $e 0.15 0.9 $dur ((Get-Random -Minimum 0 -Maximum 30) / 10.0)
  }
}

# Distant neon-rimmed mountain ridge resting on the horizon. Dark near-card fill so
# the grid reads in front of it; a thin neon-cyan stroke gives the wireframe edge.
function Add-VaporwaveMountains($canvas, [double]$w, [double]$h, [double]$opacity) {
  $horizon = $h * 0.52
  $data = New-MountainPathData $w $horizon ($horizon - $h * 0.16) 5
  $path = New-Object System.Windows.Shapes.Path
  $path.Data = [System.Windows.Media.Geometry]::Parse($data)
  $path.Fill = New-Brush '#CC160F1F'
  $path.Stroke = New-Brush '#FF01CDFE'
  $path.StrokeThickness = 1.2
  $path.Opacity = [Math]::Min(1.0, $opacity * 2.2)
  [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
  $canvas.Children.Add($path) | Out-Null
}

# Receding neon perspective grid, "riding the floor" outrun style. The vertical rays
# converge to the vanishing point on the horizon and stay FIXED; the horizontal lines
# flow toward the viewer — emerging faint at the horizon and accelerating to the bottom
# on a quadratic perspective curve (y = horizon + span * t^2), so they tighten/slow far
# away and spread/rush up close. Each rides one cycle then loops; they are staggered so
# the floor is always covered, and the group is clipped to the card so lines vanish at
# the bottom edge and the wrap back to the horizon happens off-screen (seamless).
function Add-VaporwaveGrid($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $horizon = $h * 0.52
  $span = $h - $horizon
  $op = [Math]::Min(1.0, $opacity * 2.0)
  $neon = '#FF01CDFE'

  $grid = New-Object System.Windows.Controls.Canvas
  $grid.Width = $w; $grid.Height = $h; $grid.ClipToBounds = $true   # horizontals exit at the bottom edge
  [System.Windows.Controls.Canvas]::SetLeft($grid, 0); [System.Windows.Controls.Canvas]::SetTop($grid, 0)
  $canvas.Children.Add($grid) | Out-Null

  # Static vertical rays: vanishing point -> evenly spaced bottom points (rows = 0).
  $verts = New-Object System.Windows.Shapes.Path
  $verts.Data = [System.Windows.Media.Geometry]::Parse((New-GridPathData $w $horizon $h 12 0 ($w * 0.5)))
  $verts.Stroke = New-Brush $neon
  $verts.StrokeThickness = 1.0
  $verts.Opacity = $op
  $grid.Children.Add($verts) | Out-Null

  # Flowing horizontals: full-width lines translated from the horizon to just past the
  # bottom along t^2, looping forever, phase-staggered by a negative BeginTime.
  $rows = 14
  $cycle = 5.0 / $speed
  $steps = 14
  for ($i = 0; $i -lt $rows; $i++) {
    $line = New-Object System.Windows.Shapes.Line
    $line.X1 = 0; $line.X2 = $w; $line.Y1 = 0; $line.Y2 = 0
    $line.Stroke = New-Brush $neon
    $line.StrokeThickness = 1.0
    $line.Opacity = 0
    $tt = New-Object System.Windows.Media.TranslateTransform 0, $horizon
    $line.RenderTransform = $tt
    $grid.Children.Add($line) | Out-Null

    $dur = [System.Windows.Duration][TimeSpan]::FromSeconds($cycle)
    $begin = [TimeSpan]::FromSeconds( -($i / [double]$rows) * $cycle )

    # Y: horizon -> h + a hair (clipped) along the perspective curve.
    $move = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $move.Duration = $dur; $move.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $move.BeginTime = $begin
    for ($k = 0; $k -le $steps; $k++) {
      $t = $k / [double]$steps
      $y = $horizon + ($span * 1.06) * $t * $t
      $kt = [System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * $t)
      $move.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $y, $kt)) | Out-Null
    }
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $move)

    # Opacity: fade in at the horizon so a line never pops into existence; full brightness
    # the rest of the way (the bottom wrap is hidden by the clip, off-screen).
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $fade.Duration = $dur; $fade.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $fade.BeginTime = $begin
    $fade.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds(0)))) | Out-Null
    $fade.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $op,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.15)))) | Out-Null
    $fade.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame $op,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle)))) | Out-Null
    $line.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
  }
}

# Angular palm silhouettes framing the bottom corners. Straight-segment fronds drawn
# inline (no curves -> no geometry helper needed). Invariant culture so the inline
# path coords keep '.' decimals. Off by default: the palm hero already owns the motif.
function Add-VaporwavePalms($canvas, [double]$w, [double]$h) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  $fill = New-Brush '#E60D0A14'
  $palm = {
    param([double]$bx, [double]$by, [double]$ph, [int]$dir)
    $tw = $ph * 0.05
    $crownY = $by - $ph
    $cx = $bx + $dir * $ph * 0.08
    $d = "M $(&$f ($bx - $tw)),$(&$f $by) " +
         "L $(&$f ($bx + $tw)),$(&$f $by) " +
         "L $(&$f ($cx + $tw)),$(&$f $crownY) " +
         "L $(&$f ($cx - $tw)),$(&$f $crownY) Z"
    $fronds = @(@(-0.42, -0.10), @(-0.22, 0.16), @(0.0, 0.30), @(0.22, 0.16), @(0.42, -0.10))
    foreach ($fr in $fronds) {
      $tipX = $cx + $ph * $fr[0]
      $tipY = $crownY - $ph * 0.34 + $ph * $fr[1]
      $d += " M $(&$f $cx),$(&$f $crownY) " +
            "L $(&$f $tipX),$(&$f $tipY) " +
            "L $(&$f ($cx + $ph * $fr[0] * 0.5)),$(&$f ($crownY - $ph * 0.04)) Z"
    }
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = [System.Windows.Media.Geometry]::Parse($d)
    $p.Fill = $fill
    [System.Windows.Controls.Canvas]::SetLeft($p, 0); [System.Windows.Controls.Canvas]::SetTop($p, 0)
    $canvas.Children.Add($p) | Out-Null
  }
  & $palm ($w * 0.10) $h ($h * 0.42) (-1)
  & $palm ($w * 0.90) $h ($h * 0.42) (1)
}

# VHS scanlines: thin dark horizontal lines across the whole card, rolling slowly
# downward. The roll loops seamlessly by translating exactly one line spacing (lines
# repeat every $step, and one extra line is drawn past the bottom).
function Add-VaporwaveScanlines($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $group = New-Object System.Windows.Controls.Canvas
  $step = 4.0
  $fill = New-Brush '#FF000000'
  $y = 0.0
  while ($y -lt $h + $step) {
    $line = New-Object System.Windows.Shapes.Rectangle
    $line.Width = $w; $line.Height = 1.0; $line.Fill = $fill
    [System.Windows.Controls.Canvas]::SetTop($line, $y)
    $group.Children.Add($line) | Out-Null
    $y += $step
  }
  $group.Opacity = [Math]::Min(0.5, $opacity * 1.1)
  [System.Windows.Controls.Canvas]::SetLeft($group, 0); [System.Windows.Controls.Canvas]::SetTop($group, 0)
  $tt = New-Object System.Windows.Media.TranslateTransform
  $group.RenderTransform = $tt
  $canvas.Children.Add($group) | Out-Null
  $drift = New-Object System.Windows.Media.Animation.DoubleAnimation 0, $step, ([System.Windows.Duration][TimeSpan]::FromSeconds(6.0 / $speed))
  $drift.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $drift)
}

# Neon bloom band along the horizon: a wide rectangle with a vertical transparent ->
# cyan -> transparent gradient, flickering subtly via Add-Twinkle.
function Add-VaporwaveGlow($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $horizon = $h * 0.52
  $bandH = $h * 0.18
  $r = New-Object System.Windows.Shapes.Rectangle
  $r.Width = $w; $r.Height = $bandH
  $g = New-Object System.Windows.Media.LinearGradientBrush
  $g.StartPoint = '0,0'; $g.EndPoint = '0,1'
  $g.GradientStops.Add((New-SceneStop '#0001CDFE' 0.0))
  $g.GradientStops.Add((New-SceneStop '#9901CDFE' 0.5))
  $g.GradientStops.Add((New-SceneStop '#0001CDFE' 1.0))
  $r.Fill = $g
  [System.Windows.Controls.Canvas]::SetLeft($r, 0); [System.Windows.Controls.Canvas]::SetTop($r, $horizon - $bandH / 2)
  $canvas.Children.Add($r) | Out-Null
  Add-Twinkle $r ([Math]::Min(0.9, $opacity * 1.4)) ([Math]::Min(1.0, $opacity * 2.0)) (4.5 / $speed) 0
}

# Render the vaporwave scene into $box.Scene. $cfg: @{ colors; opacity; speed; + the
# eight layer flags }. Back-to-front draw order; called from a Loaded handler so the
# card ActualWidth/Height are known. Nothing draws unless its flag is set.
function Start-Vaporwave($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }

  $opacity = [double]$cfg.opacity; if ($opacity -le 0) { $opacity = 0.22 }
  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }

  $canvas.Width = $w; $canvas.Height = $h

  if ($cfg.haze)      { Add-VaporwaveHaze      $canvas $w $h }
  if ($cfg.sun)       { Add-VaporwaveSun       $canvas $w $h $speed }
  if ($cfg.stars)     { Add-VaporwaveStars     $canvas $w $h $speed }
  if ($cfg.mountains) { Add-VaporwaveMountains $canvas $w $h $opacity }
  if ($cfg.grid)      { Add-VaporwaveGrid      $canvas $w $h $opacity $speed }
  if ($cfg.palms)     { Add-VaporwavePalms     $canvas $w $h }
  if ($cfg.scanlines) { Add-VaporwaveScanlines $canvas $w $h $opacity $speed }
  if ($cfg.glow)      { Add-VaporwaveGlow      $canvas $w $h $opacity $speed }
}
