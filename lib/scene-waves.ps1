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
