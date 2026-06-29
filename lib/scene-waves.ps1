# Scenery renderer: ocean "waves". New-WavePathData is WPF-free + unit-tested;
# Start-Waves consumes it. Dot-sourced by show-notification.ps1.

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

# Render + animate the waves into $box.Scene. $cfg: @{ colors=@('#..'); opacity=<0..1>; speed=<num> }.
# Called from a Loaded handler so $box.Card.ActualWidth/Height are known.
function Start-Waves($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }

  $colors = @($cfg.colors); if ($colors.Count -eq 0) { $colors = @('#0EA5E9', '#22D3EE', '#2DD4BF') }
  $opacity = [double]$cfg.opacity; if ($opacity -le 0) { $opacity = 0.22 }
  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }

  $canvas.Width = $w; $canvas.Height = $h; $canvas.Opacity = $opacity

  # Three layers: back (slow/tall) to front (fast/short) for parallax depth.
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
    $path.Opacity = 0.6   # per-layer translucency, multiplies the canvas opacity
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
