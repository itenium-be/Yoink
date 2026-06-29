# Scenery renderer: sakura — falling cherry-blossom petals + optional bloom glow,
# corner branch and parallax foreground petals. New-PetalPathData / New-SakuraStop
# are the pure bits (unit-tested); the Add-Sakura* helpers and Start-Sakura build
# live WPF visuals. Dot-sourced by show-notification.ps1; New-Brush comes from
# notification-box.ps1.

# One cherry-blossom petal as XAML path geometry: a rounded body tapering to a
# notched tip, pointing up, base at the bottom-centre. Coordinates are SPACE-
# separated and formatted with the invariant culture: the nl-BE machine locale
# would emit ',' decimals and Geometry.Parse would choke (see New-WavePathData).
function New-PetalPathData([double]$w, [double]$h) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $n = { param($v) ([double]$v).ToString('0.###', $ic) }
  $cx = $w / 2.0
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("M $(& $n $cx) $(& $n $h) ")
  # Up the left flank to the notched tip (tip dips to h*0.16 at centre).
  [void]$sb.Append("C $(& $n ($w*0.04)) $(& $n ($h*0.58)) $(& $n ($w*0.16)) $(& $n ($h*0.06)) $(& $n $cx) $(& $n ($h*0.16)) ")
  # Down the right flank back to the base.
  [void]$sb.Append("C $(& $n ($w*0.84)) $(& $n ($h*0.06)) $(& $n ($w*0.96)) $(& $n ($h*0.58)) $(& $n $cx) $(& $n $h) ")
  [void]$sb.Append('Z')
  $sb.ToString()
}

# Gradient stop with a 0..1 alpha baked into #AARRGGBB (lets the bloom glows fade
# to transparent without a separate Opacity per stop). Mirrors New-SpaceStop.
function New-SakuraStop([string]$hex6, [double]$alpha, [double]$offset) {
  $a = [int][Math]::Round(255 * $alpha)
  $argb = ('#{0:X2}{1}' -f $a, $hex6.TrimStart('#'))
  New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($argb)), $offset
}
