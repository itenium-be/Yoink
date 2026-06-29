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
