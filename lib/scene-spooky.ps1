# Scenery renderer: spooky — eight independent, flag-toggled Halloween/haunted
# layers. New-WebPathData / New-BatPathData are WPF-free + unit-tested; the
# Add-Spooky* helpers build live WPF visuals. Dot-sourced by show-notification.ps1.

# XAML path geometry for a corner spiderweb: `spokes` radial threads fanning 0..90deg
# from (cx,cy), plus `rings` concentric polyline threads connecting the spokes at
# fractional radii. One combined Path data string (multiple M subpaths), stroked.
# Invariant culture: XAML needs '.' decimals; nl-BE would emit ',' and choke Parse.
function New-WebPathData([double]$cx, [double]$cy, [double]$r, [int]$spokes, [int]$rings) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  if ($spokes -lt 2) { $spokes = 2 }
  if ($rings -lt 1) { $rings = 1 }
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  $angles = @()
  for ($s = 0; $s -lt $spokes; $s++) {
    $t = $s / ($spokes - 1)
    $angles += (90.0 * $t)
  }
  $sb = New-Object System.Text.StringBuilder
  foreach ($deg in $angles) {
    $rad = $deg * [Math]::PI / 180.0
    $x = $cx + $r * [Math]::Cos($rad)
    $y = $cy + $r * [Math]::Sin($rad)
    [void]$sb.Append(("M {0},{1} L {2},{3} " -f (&$f $cx), (&$f $cy), (&$f $x), (&$f $y)))
  }
  for ($ringi = 1; $ringi -le $rings; $ringi++) {
    $rr = $r * $ringi / ($rings + 1)
    for ($s = 0; $s -lt $spokes; $s++) {
      $rad = $angles[$s] * [Math]::PI / 180.0
      $x = $cx + $rr * [Math]::Cos($rad)
      $y = $cy + $rr * [Math]::Sin($rad)
      $cmd = if ($s -eq 0) { 'M' } else { 'L' }
      [void]$sb.Append(("{0} {1},{2} " -f $cmd, (&$f $x), (&$f $y)))
    }
  }
  $sb.ToString().TrimEnd()
}

# Filled, closed bat silhouette centred on (0,0): a small body with two scalloped
# wings. Right side is built explicitly then mirrored to the left, so the shape is
# symmetric. Wing tips reach +/-w/2; the bottom reaches +h/2, the top is shallower.
function New-BatPathData([double]$w, [double]$h) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $hw = $w / 2; $hh = $h / 2
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  # Right half, top-of-head -> outer wing -> wing notch -> bottom-of-body.
  $right =
    "L $(&$f ($hw*0.15)),$(&$f (-$hh*0.55)) " +   # right ear/shoulder
    "L $(&$f ($hw*0.40)),$(&$f (-$hh*0.15)) " +   # inner wing
    "L $(&$f ($hw*0.75)),$(&$f (-$hh*0.45)) " +   # outer wing rise (-> 37.5,... for hw=50)
    "L $(&$f $hw),$(&$f (-$hh*0.10)) " +          # wing tip (+hw)
    "L $(&$f ($hw*0.70)),$(&$f ($hh*0.35)) " +    # scallop
    "L $(&$f ($hw*0.30)),$(&$f ($hh*0.10)) " +    # back toward body
    "L 0,$(&$f $hh) "                              # bottom of body
  $left =
    "L $(&$f (-$hw*0.30)),$(&$f ($hh*0.10)) " +
    "L $(&$f (-$hw*0.70)),$(&$f ($hh*0.35)) " +
    "L $(&$f (-$hw)),$(&$f (-$hh*0.10)) " +        # wing tip (-hw)
    "L $(&$f (-$hw*0.75)),$(&$f (-$hh*0.45)) " +
    "L $(&$f (-$hw*0.40)),$(&$f (-$hh*0.15)) " +
    "L $(&$f (-$hw*0.15)),$(&$f (-$hh*0.55)) "
  "M 0,$(&$f (-$hh*0.30)) " + $right + $left + "Z"
}

# --- layers (back to front) --------------------------------------------------

# Pale full moon with a soft halo in the upper-right; gentle opacity pulse.
# Mirrors Add-OceanSun but cold-white and right-anchored.
function Add-SpookyMoon($canvas, [double]$w, [double]$h, [double]$speed) {
  $d = $h * 0.5
  $e = New-Object System.Windows.Shapes.Ellipse
  $e.Width = $d; $e.Height = $d
  $rg = New-Object System.Windows.Media.RadialGradientBrush
  $rg.GradientStops.Add((New-SceneStop '#FFF7F0E0' 0.0))
  $rg.GradientStops.Add((New-SceneStop '#66E8E0C8' 0.45))
  $rg.GradientStops.Add((New-SceneStop '#00E8E0C8' 1.0))
  $e.Fill = $rg
  [System.Windows.Controls.Canvas]::SetLeft($e, $w * 0.84 - $d / 2)
  [System.Windows.Controls.Canvas]::SetTop($e, $h * 0.20 - $d / 2)
  $canvas.Children.Add($e) | Out-Null
  $pulse = New-Object System.Windows.Media.Animation.DoubleAnimation 0.55, 0.8, ([System.Windows.Duration][TimeSpan]::FromSeconds(5.0 / $speed))
  $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $e.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $pulse)
}

# Low translucent mist bands drifting along the bottom, with a slow opacity sway.
# Reuses New-WavePathData (wavy top edge, flat filled bottom) like the aurora layer.
function Add-SpookyFog($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  for ($i = 0; $i -lt 2; $i++) {
    $top = $h * (0.74 + 0.10 * $i)
    $amp = $h * 0.03
    $period = $w * (0.9 + 0.3 * $i)
    $pathW = $w + $period
    $data = New-WavePathData $pathW $period $amp $top $h ([Math]::Max(4.0, $period / 24.0))
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($data)
    $vg = New-Object System.Windows.Media.LinearGradientBrush
    $vg.StartPoint = '0,0'; $vg.EndPoint = '0,1'
    $vg.GradientStops.Add((New-SceneStop '#99B8B8C8' 0.0))
    $vg.GradientStops.Add((New-SceneStop '#33B8B8C8' 1.0))
    $path.Fill = $vg
    $path.Opacity = $opacity * (1.3 - 0.3 * $i)
    [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $path.RenderTransform = $tt
    $canvas.Children.Add($path) | Out-Null
    $dur = [System.Windows.Duration][TimeSpan]::FromSeconds((30 + 10 * $i) / $speed)
    $drift = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-$period), $dur
    $drift.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $drift)
    Add-Twinkle $path ($opacity * 0.8) ($opacity * 1.3) (6.0 + $i) ($i * 0.9)
  }
}

# Static silhouette of tilted gravestones along the bottom edge (gravestone-grey rounded rects).
function Add-SpookyGravestones($canvas, [double]$w, [double]$h) {
  $fill = New-Brush '#CC8A8F99'
  $n = 5
  for ($i = 0; $i -lt $n; $i++) {
    $gw = $w * (0.06 + ($i % 2) * 0.02)
    $gh = $h * (0.16 + ($i % 3) * 0.04)
    $r = New-Object System.Windows.Shapes.Rectangle
    $r.Width = $gw; $r.Height = $gh
    $r.RadiusX = $gw * 0.5; $r.RadiusY = $gw * 0.5
    $r.Fill = $fill
    $x = $w * (0.05 + 0.2 * $i)
    [System.Windows.Controls.Canvas]::SetLeft($r, $x)
    [System.Windows.Controls.Canvas]::SetTop($r, $h - $gh + $gh * 0.25)
    $rt = New-Object System.Windows.Media.RotateTransform (($i % 2) * 6 - 3)
    $r.RenderTransform = $rt
    $canvas.Children.Add($r) | Out-Null
  }
}

# Corner spiderweb (top-left): radial spokes + ring threads via New-WebPathData,
# stroked thin and faint, with a slow shimmer.
function Add-SpookyWebs($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $data = New-WebPathData 0 0 ($h * 0.7) 6 4
  $path = New-Object System.Windows.Shapes.Path
  $path.Data = [System.Windows.Media.Geometry]::Parse($data)
  $path.Stroke = New-Brush '#FFD8D8E0'
  $path.StrokeThickness = 1.0
  $path.Opacity = $opacity * 1.4
  [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
  $canvas.Children.Add($path) | Out-Null
  Add-Twinkle $path ($opacity * 1.1) ($opacity * 1.6) (7.0 / $speed) 0
}

# Pale ghost wisps rising bottom->top while fading; negative phase spreads them up
# the column at t=0. Reuses the unicorn glitter drift idiom, bigger and fewer.
function Add-SpookyGhosts($canvas, [double]$w, [double]$h, [double]$speed) {
  $n = 5
  for ($i = 0; $i -lt $n; $i++) {
    $sz = $h * (0.10 + (Get-Random -Minimum 0 -Maximum 6) / 100.0)
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $sz * 0.7; $e.Height = $sz
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-SceneStop '#CCE8E8F0' 0.0))
    $rg.GradientStops.Add((New-SceneStop '#00E8E8F0' 1.0))
    $e.Fill = $rg
    [System.Windows.Controls.Canvas]::SetLeft($e, (Get-Random -Minimum 0 -Maximum ([int]$w)))
    [System.Windows.Controls.Canvas]::SetTop($e, $h)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $e.RenderTransform = $tt
    $canvas.Children.Add($e) | Out-Null
    $rise = $h * 1.2
    $dur = 11.0 + (Get-Random -Minimum 0 -Maximum 80) / 10.0
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-$rise), ([System.Windows.Duration][TimeSpan]::FromSeconds($dur / $speed))
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $phase = $i / $n
    $anim.BeginTime = [TimeSpan]::FromSeconds( -($phase * $dur / $speed) )
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
    Add-Twinkle $e 0.2 0.75 (3.0 + (Get-Random -Minimum 0 -Maximum 20) / 10.0) ((Get-Random -Minimum 0 -Maximum 20) / 10.0)
  }
}

# Small bat silhouettes flapping diagonally across the card on a long loop; a
# scale pulse on Y fakes the wing-flap. Uses New-BatPathData.
function Add-SpookyBats($canvas, [double]$w, [double]$h, [double]$speed) {
  for ($i = 0; $i -lt 3; $i++) {
    $bw = $w * (0.06 + 0.02 * $i)
    $bh = $bw * 0.6
    $bat = New-Object System.Windows.Shapes.Path
    $bat.Data = [System.Windows.Media.Geometry]::Parse((New-BatPathData $bw $bh))
    $bat.Fill = New-Brush '#E60A0710'
    $startY = $h * (0.18 + 0.16 * $i)
    $tt = New-Object System.Windows.Media.TranslateTransform (-$bw), $startY
    $st = New-Object System.Windows.Media.ScaleTransform 1, 1
    $tg = New-Object System.Windows.Media.TransformGroup
    $tg.Children.Add($st); $tg.Children.Add($tt)
    $bat.RenderTransform = $tg
    $canvas.Children.Add($bat) | Out-Null
    $cycle = (12.0 + 3.0 * $i) / $speed
    $travelX = New-Object System.Windows.Media.Animation.DoubleAnimation (-$bw), ($w + $bw), ([System.Windows.Duration][TimeSpan]::FromSeconds($cycle))
    $travelX.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $travelX)
    $flap = New-Object System.Windows.Media.Animation.DoubleAnimation 1.0, 0.55, ([System.Windows.Duration][TimeSpan]::FromSeconds(0.35 / $speed))
    $flap.AutoReverse = $true; $flap.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $flap)
  }
}

# Pairs of glowing eyes that blink in the dark at staggered intervals (a quick dip
# to near-zero via a long-period twinkle reading as a blink).
function Add-SpookyEyes($canvas, [double]$w, [double]$h, [double]$speed) {
  $hues = @('#FFE05A', '#9CFF5A', '#FF7A18')
  for ($i = 0; $i -lt 3; $i++) {
    $sz = $h * 0.035
    $gap = $sz * 1.8
    $x = $w * (0.2 + 0.28 * $i)
    $y = $h * (0.45 + 0.12 * ($i % 2))
    $pair = New-Object System.Windows.Controls.Canvas
    foreach ($dx in @(0, $gap)) {
      $e = New-Object System.Windows.Shapes.Ellipse
      $e.Width = $sz; $e.Height = $sz
      $rg = New-Object System.Windows.Media.RadialGradientBrush
      $rg.GradientStops.Add((New-SceneStop ('#FF' + $hues[$i].Substring(1)) 0.0))
      $rg.GradientStops.Add((New-SceneStop ('#00' + $hues[$i].Substring(1)) 1.0))
      $e.Fill = $rg
      [System.Windows.Controls.Canvas]::SetLeft($e, $dx)
      $pair.Children.Add($e) | Out-Null
    }
    [System.Windows.Controls.Canvas]::SetLeft($pair, $x)
    [System.Windows.Controls.Canvas]::SetTop($pair, $y)
    $canvas.Children.Add($pair) | Out-Null
    Add-Twinkle $pair 0.15 0.95 ((3.5 + $i) / $speed) ($i * 1.3)
  }
}

# Occasional full-card lightning flash with a long idle gap: opacity keyframes spike
# briefly then sit dark until the loop repeats (same gating idiom as shootingStar).
function Add-SpookyLightning($canvas, [double]$w, [double]$h, [double]$speed) {
  $r = New-Object System.Windows.Shapes.Rectangle
  $r.Width = $w; $r.Height = $h
  $r.Fill = New-Brush '#FFEFE6FF'
  $r.Opacity = 0
  [System.Windows.Controls.Canvas]::SetLeft($r, 0); [System.Windows.Controls.Canvas]::SetTop($r, 0)
  $canvas.Children.Add($r) | Out-Null
  $cycle = 11.0 / $speed
  $op = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
  $op.Duration = [System.Windows.Duration][TimeSpan]::FromSeconds($cycle)
  $op.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds(0)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.45, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.02)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.06)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.5,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.10)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.16)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle)))) | Out-Null
  $r.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $op)
}

# Render the spooky scene into $box.Scene. $cfg: @{ colors; opacity; speed; + the
# eight layer flags }. Back-to-front draw order; called from a Loaded handler so the
# card ActualWidth/Height are known. Nothing draws unless its flag is set.
function Start-Spooky($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }

  $opacity = [double]$cfg.opacity; if ($opacity -le 0) { $opacity = 0.22 }
  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }

  $canvas.Width = $w; $canvas.Height = $h

  if ($cfg.moon)        { Add-SpookyMoon        $canvas $w $h $speed }
  if ($cfg.fog)         { Add-SpookyFog         $canvas $w $h $opacity $speed }
  if ($cfg.gravestones) { Add-SpookyGravestones $canvas $w $h }
  if ($cfg.webs)        { Add-SpookyWebs        $canvas $w $h $opacity $speed }
  if ($cfg.ghosts)      { Add-SpookyGhosts      $canvas $w $h $speed }
  if ($cfg.bats)        { Add-SpookyBats        $canvas $w $h $speed }
  if ($cfg.eyes)        { Add-SpookyEyes        $canvas $w $h $speed }
  if ($cfg.lightning)   { Add-SpookyLightning   $canvas $w $h $speed }
}
