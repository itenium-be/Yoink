# Scenery renderer: dragon — rising embers + optional fire glow, flame tongues and
# smoke wisps. New-FlamePathData / New-DragonStop are the pure bits (unit-tested);
# the Add-Dragon* helpers and Start-Dragon build live WPF visuals. Dot-sourced by
# show-notification.ps1; New-Brush comes from notification-box.ps1.

# One flame tongue as XAML path geometry: a teardrop tapering to a point at the top,
# base at the bottom-centre. Coordinates are SPACE-separated and formatted with the
# invariant culture (the nl-BE machine locale would emit ',' decimals and
# Geometry.Parse would choke — see New-WavePathData).
function New-FlamePathData([double]$w, [double]$h) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $n = { param($v) ([double]$v).ToString('0.###', $ic) }
  $cx = $w / 2.0
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("M $(& $n $cx) $(& $n $h) ")
  # Up the left flank, curling inward to the pointed tip.
  [void]$sb.Append("C $(& $n ($w*0.02)) $(& $n ($h*0.62)) $(& $n ($w*0.28)) $(& $n ($h*0.26)) $(& $n $cx) $(& $n 0) ")
  # Down the right flank back to the base.
  [void]$sb.Append("C $(& $n ($w*0.72)) $(& $n ($h*0.26)) $(& $n ($w*0.98)) $(& $n ($h*0.62)) $(& $n $cx) $(& $n $h) ")
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
