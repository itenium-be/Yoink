# Scenery renderer: unicorn — eight independent, flag-toggled layers spanning four
# motifs (rainbow / aurora night / glitter / pastel). New-ArcPathData is WPF-free +
# unit-tested; the Add-Unicorn* helpers build live WPF visuals. Dot-sourced by
# show-notification.ps1.

# Build XAML path geometry for one rainbow band: an OPEN polyline sampled along a
# circular arc (stroked, not filled, so no closing Z). Sweeps a0Deg->a1Deg about
# (cx,cy); with screen y-down, a 180->360 sweep arches upward into a dome.
# Invariant culture: XAML needs '.' decimals, but nl-BE would emit ',' and choke Parse.
function New-ArcPathData([double]$cx, [double]$cy, [double]$r, [double]$a0Deg, [double]$a1Deg, [double]$step) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  if ($step -le 0) { $step = 4 }
  $sb = New-Object System.Text.StringBuilder
  $a = $a0Deg; $first = $true
  while ($a -le $a1Deg) {
    $rad = $a * [Math]::PI / 180.0
    $x = $cx + $r * [Math]::Cos($rad)
    $y = $cy + $r * [Math]::Sin($rad)
    $cmd = if ($first) { 'M' } else { 'L' }
    [void]$sb.Append(("{0} {1},{2} " -f $cmd, $x.ToString('0.##', $ic), $y.ToString('0.##', $ic)))
    $first = $false
    $a += $step
  }
  $sb.ToString().TrimEnd()
}

# --- shared little helpers ---------------------------------------------------

# A staggered, auto-reversing opacity "twinkle" that loops forever. Used by stars,
# glitter and sparkles so their fades never march in lockstep.
function Add-Twinkle($el, [double]$lo, [double]$hi, [double]$seconds, [double]$beginOffset) {
  $el.Opacity = $lo
  $a = New-Object System.Windows.Media.Animation.DoubleAnimation $lo, $hi, ([System.Windows.Duration][TimeSpan]::FromSeconds($seconds))
  $a.AutoReverse = $true
  $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $a.BeginTime = [TimeSpan]::FromSeconds($beginOffset)
  $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
}

# A 4-point sparkle (two tapered diamonds) as a filled Path, centred on (0,0).
function New-SparkleVisual([double]$size, [string]$hex) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $R = $size; $i = $size * 0.2
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  $d = "M 0,$(&$f (-$R)) L $(&$f $i),$(&$f (-$i)) L $(&$f $R),0 L $(&$f $i),$(&$f $i) " +
       "L 0,$(&$f $R) L $(&$f (-$i)),$(&$f $i) L $(&$f (-$R)),0 L $(&$f (-$i)),$(&$f (-$i)) Z"
  $p = New-Object System.Windows.Shapes.Path
  $p.Data = [System.Windows.Media.Geometry]::Parse($d)
  $p.Fill = New-Brush $hex
  $p
}

# --- layers (back to front) --------------------------------------------------

# Pastel dawn gradient backdrop (lavender -> pink -> mint -> peach), translucent so
# the dark card never fully disappears and centred text stays legible.
function Add-UnicornSky($canvas, [double]$w, [double]$h) {
  $r = New-Object System.Windows.Shapes.Rectangle
  $r.Width = $w; $r.Height = $h
  $g = New-Object System.Windows.Media.LinearGradientBrush
  $g.StartPoint = '0,0'; $g.EndPoint = '0,1'
  $g.GradientStops.Add((New-SceneStop '#CCB794F4' 0.0))
  $g.GradientStops.Add((New-SceneStop '#99FBC2EB' 0.4))
  $g.GradientStops.Add((New-SceneStop '#66A0E7E5' 0.72))
  $g.GradientStops.Add((New-SceneStop '#66FFDAC1' 1.0))
  $r.Fill = $g
  [System.Windows.Controls.Canvas]::SetLeft($r, 0); [System.Windows.Controls.Canvas]::SetTop($r, 0)
  $canvas.Children.Add($r) | Out-Null
}

# Aurora curtains: translucent wavy bands high in the card, each fading downward to
# transparent, drifting sideways at staggered speeds with a slow opacity sway.
function Add-UnicornAurora($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $hues = @('#7CFFB2', '#5EEAD4', '#A78BFA')
  for ($i = 0; $i -lt 3; $i++) {
    $top = $h * (0.10 + 0.08 * $i)
    $amp = $h * 0.05
    $period = $w * (0.8 + 0.2 * $i)
    $bottom = $top + $h * 0.30
    $pathW = $w + $period
    $data = New-WavePathData $pathW $period $amp $top $bottom ([Math]::Max(4.0, $period / 24.0))
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($data)
    $vg = New-Object System.Windows.Media.LinearGradientBrush
    $vg.StartPoint = '0,0'; $vg.EndPoint = '0,1'
    $col = [System.Windows.Media.ColorConverter]::ConvertFromString($hues[$i])
    $top2 = [System.Windows.Media.Color]::FromArgb(180, $col.R, $col.G, $col.B)
    $bot2 = [System.Windows.Media.Color]::FromArgb(0, $col.R, $col.G, $col.B)
    $vg.GradientStops.Add((New-Object System.Windows.Media.GradientStop $top2, 0.0))
    $vg.GradientStops.Add((New-Object System.Windows.Media.GradientStop $bot2, 1.0))
    $path.Fill = $vg
    $path.Opacity = $opacity * 1.4
    [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $path.RenderTransform = $tt
    $canvas.Children.Add($path) | Out-Null
    $dur = [System.Windows.Duration][TimeSpan]::FromSeconds((26 + 8 * $i) / $speed)
    $drift = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-$period), $dur
    $drift.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $drift)
    Add-Twinkle $path ($opacity * 1.0) ($opacity * 1.6) (5.0 + $i) ($i * 0.7)
  }
}

# Soft ROYGBIV arch over the top. Concentric stroked arcs (fixed spectrum hues read
# truer than the theme palette), wrapped in a container that pulses gently.
function Add-UnicornRainbow($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $hues = @('#FF595E', '#FF924C', '#FFCA3A', '#8AC926', '#1982C4', '#4267AC', '#6A4C93')
  $group = New-Object System.Windows.Controls.Canvas
  $cx = $w * 0.5; $cy = $h * 1.02
  $outer = $h * 0.92
  $band = ($h * 0.30) / $hues.Count
  for ($i = 0; $i -lt $hues.Count; $i++) {
    $r = $outer - $i * $band
    $data = New-ArcPathData $cx $cy $r 200 340 4
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($data)
    $path.Stroke = New-Brush $hues[$i]
    $path.StrokeThickness = $band * 1.1
    $path.StrokeStartLineCap = 'Round'; $path.StrokeEndLineCap = 'Round'
    $group.Children.Add($path) | Out-Null
  }
  $group.Opacity = $opacity * 1.5
  $canvas.Children.Add($group) | Out-Null
  Add-Twinkle $group ($opacity * 1.3) ($opacity * 1.8) (6.0 / $speed) 0
}

# Field of tiny twinkling dots at fixed positions.
function Add-UnicornStars($canvas, [double]$w, [double]$h, [double]$speed) {
  for ($i = 0; $i -lt 42; $i++) {
    $sz = 1.5 + (Get-Random -Minimum 0 -Maximum 20) / 10.0
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $sz; $e.Height = $sz; $e.Fill = New-Brush '#FFFFFF'
    [System.Windows.Controls.Canvas]::SetLeft($e, (Get-Random -Minimum 0 -Maximum ([int]$w)))
    [System.Windows.Controls.Canvas]::SetTop($e, (Get-Random -Minimum 0 -Maximum ([int]$h)))
    $canvas.Children.Add($e) | Out-Null
    $dur = (1.6 + (Get-Random -Minimum 0 -Maximum 30) / 10.0) / $speed
    Add-Twinkle $e 0.15 0.95 $dur ((Get-Random -Minimum 0 -Maximum 30) / 10.0)
  }
}

# Tiny pastel particles drifting up from the bottom while twinkling. Negative phase
# spreads them up the column at t=0 instead of all starting at the floor.
function Add-UnicornGlitter($canvas, [double]$w, [double]$h, $colors, [double]$speed) {
  $n = 30
  for ($i = 0; $i -lt $n; $i++) {
    $sz = 2 + (Get-Random -Minimum 0 -Maximum 30) / 10.0
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $sz; $e.Height = $sz; $e.Fill = New-Brush ($colors[$i % $colors.Count])
    [System.Windows.Controls.Canvas]::SetLeft($e, (Get-Random -Minimum 0 -Maximum ([int]$w)))
    [System.Windows.Controls.Canvas]::SetTop($e, $h)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $e.RenderTransform = $tt
    $canvas.Children.Add($e) | Out-Null
    $rise = $h * 1.15
    $dur = 9.0 + (Get-Random -Minimum 0 -Maximum 80) / 10.0
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-$rise), ([System.Windows.Duration][TimeSpan]::FromSeconds($dur / $speed))
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $phase = ($i + (Get-Random -Minimum 0 -Maximum 60) / 100.0) / $n
    $anim.BeginTime = [TimeSpan]::FromSeconds( -($phase * $dur / $speed) )
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
    Add-Twinkle $e 0.25 0.9 (2.0 + (Get-Random -Minimum 0 -Maximum 20) / 10.0) ((Get-Random -Minimum 0 -Maximum 20) / 10.0)
  }
}

# Fewer, larger 4-point glints scattered mid-card; twinkle + a gentle scale pulse.
function Add-UnicornSparkles($canvas, [double]$w, [double]$h, $colors, [double]$speed) {
  for ($i = 0; $i -lt 9; $i++) {
    $sz = 6 + (Get-Random -Minimum 0 -Maximum 70) / 10.0
    $sp = New-SparkleVisual $sz ($colors[$i % $colors.Count])
    $x = Get-Random -Minimum ([int]($w * 0.08)) -Maximum ([int]($w * 0.92))
    $y = Get-Random -Minimum ([int]($h * 0.12)) -Maximum ([int]($h * 0.88))
    [System.Windows.Controls.Canvas]::SetLeft($sp, $x)
    [System.Windows.Controls.Canvas]::SetTop($sp, $y)
    $st = New-Object System.Windows.Media.ScaleTransform 1, 1
    $sp.RenderTransform = $st
    $canvas.Children.Add($sp) | Out-Null
    $period = (2.4 + (Get-Random -Minimum 0 -Maximum 25) / 10.0) / $speed
    $begin = (Get-Random -Minimum 0 -Maximum 30) / 10.0
    Add-Twinkle $sp 0.2 0.95 $period $begin
    $pulse = New-Object System.Windows.Media.Animation.DoubleAnimation 0.7, 1.15, ([System.Windows.Duration][TimeSpan]::FromSeconds($period))
    $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $pulse.BeginTime = [TimeSpan]::FromSeconds($begin)
    $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pulse)
    $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pulse)
  }
}

# An occasional diagonal shooting star: a tapered streak that crosses the upper card
# and fades, idle most of the loop. Position loops steadily; opacity keyframes gate
# the brief visible window so it reads as periodic, not continuous.
function Add-UnicornShootingStar($canvas, [double]$w, [double]$h, [double]$speed) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $len = $w * 0.22
  $streak = New-Object System.Windows.Shapes.Path
  $streak.Data = [System.Windows.Media.Geometry]::Parse(("M 0,0 L {0},{1}" -f $len.ToString('0.##', $ic), ($len * 0.5).ToString('0.##', $ic)))
  $tail = New-Object System.Windows.Media.LinearGradientBrush
  $tail.StartPoint = '0,0'; $tail.EndPoint = '1,1'
  $tail.GradientStops.Add((New-SceneStop '#00FFFFFF' 0.0))
  $tail.GradientStops.Add((New-SceneStop '#FFFFFFFF' 1.0))
  $streak.Stroke = $tail; $streak.StrokeThickness = 2.2
  $streak.StrokeEndLineCap = 'Round'
  [System.Windows.Controls.Canvas]::SetTop($streak, 0)
  $tt = New-Object System.Windows.Media.TranslateTransform (-$len), ($h * 0.08)
  $streak.RenderTransform = $tt
  $streak.Opacity = 0
  $canvas.Children.Add($streak) | Out-Null

  $cycle = 9.0 / $speed
  $travelX = New-Object System.Windows.Media.Animation.DoubleAnimation (-$len), $w, ([System.Windows.Duration][TimeSpan]::FromSeconds($cycle))
  $travelX.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $travelX)
  $travelY = New-Object System.Windows.Media.Animation.DoubleAnimation ($h * 0.08), ($h * 0.55), ([System.Windows.Duration][TimeSpan]::FromSeconds($cycle))
  $travelY.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $travelY)
  # Visible only for the first ~18% of each cycle, then dark until it loops.
  $op = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
  $op.Duration = [System.Windows.Duration][TimeSpan]::FromSeconds($cycle)
  $op.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds(0)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.95, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.04)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.18)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle)))) | Out-Null
  $streak.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $op)
}

# Render the unicorn scene into $box.Scene. $cfg: @{ colors; opacity; speed; + the
# eight layer flags }. Back-to-front draw order; called from a Loaded handler so the
# card ActualWidth/Height are known. Nothing draws unless its flag is set.
function Start-Unicorn($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }

  $colors = @($cfg.colors); if ($colors.Count -eq 0) { $colors = @('#FFFFFF', '#FFD1DC', '#C9B6FF', '#B5EAD7', '#FFDAC1') }
  $opacity = [double]$cfg.opacity; if ($opacity -le 0) { $opacity = 0.22 }
  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }

  $canvas.Width = $w; $canvas.Height = $h

  if ($cfg.sky)          { Add-UnicornSky          $canvas $w $h }
  if ($cfg.aurora)       { Add-UnicornAurora       $canvas $w $h $opacity $speed }
  if ($cfg.rainbow)      { Add-UnicornRainbow      $canvas $w $h $opacity $speed }
  if ($cfg.clouds)       { Add-OceanClouds         $canvas $w $h $speed }
  if ($cfg.stars)        { Add-UnicornStars        $canvas $w $h $speed }
  if ($cfg.glitter)      { Add-UnicornGlitter      $canvas $w $h $colors $speed }
  if ($cfg.sparkles)     { Add-UnicornSparkles     $canvas $w $h $colors $speed }
  if ($cfg.shootingStar) { Add-UnicornShootingStar $canvas $w $h $speed }
}
