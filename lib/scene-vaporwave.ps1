# Scenery renderer: vaporwave — eight independent, flag-toggled 80s/outrun layers.
# New-GridPathData / New-MountainPathData are WPF-free + unit-tested; the Add-Vaporwave*
# helpers (added in later tasks) build live WPF visuals. Dot-sourced by show-notification.ps1.

# XAML path geometry for a receding perspective grid: `cols`+1 vertical threads
# fanning from the vanishing point (vanishX, horizonY) to evenly-spaced points along
# the bottom edge, plus `rows` full-width horizontal threads whose spacing tightens
# toward the horizon (y = horizonY + (bottomY-horizonY) * (r/rows)^2). One combined
# Path data string (multiple M subpaths), stroked.
# Invariant culture: XAML needs '.' decimals; nl-BE would emit ',' and choke Parse.
function New-GridPathData([double]$w, [double]$horizonY, [double]$bottomY, [int]$cols, [int]$rows, [double]$vanishX) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  if ($cols -lt 1) { $cols = 1 }
  if ($rows -lt 1) { $rows = 1 }
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
