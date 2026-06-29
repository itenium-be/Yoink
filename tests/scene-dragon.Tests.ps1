Add-Type -AssemblyName PresentationCore, WindowsBase
. "$PSScriptRoot\..\lib\scene-dragon.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# A closed XAML path with invariant (space-separated, '.') coordinates that WPF parses,
# also under the nl-BE comma-decimal machine locale.
function Assert-Geometry($fn, $msg) {
  $d = & $fn
  Assert-True ($d.StartsWith('M')) "$msg starts with M"
  Assert-True ($d.TrimEnd().EndsWith('Z')) "$msg closed with Z"
  Assert-True (-not $d.Contains(',')) "$msg no ',' (space-separated, invariant decimals)"
  Assert-True ($d.Contains('.')) "$msg uses '.' decimal"
  $p = $null; try { $p = [System.Windows.Media.Geometry]::Parse($d) } catch { }
  Assert-True ($null -ne $p) "$msg Geometry.Parse accepts it"
  $prev = [System.Threading.Thread]::CurrentThread.CurrentCulture
  try {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('nl-BE')
    $dc = & $fn
    Assert-True (-not $dc.Contains(',')) "$msg nl-BE: still no ',' decimal"
    $pc = $null; try { $pc = [System.Windows.Media.Geometry]::Parse($dc) } catch { }
    Assert-True ($null -ne $pc) "$msg nl-BE: still parses"
  } finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $prev }
}

# --- New-GemPathData: a faceted gem outline (table top, pointed pavilion) ---
Assert-Geometry { New-GemPathData 12 10 } "gem"

# --- New-GlintPathData: a 4-point sparkle star ---
Assert-Geometry { New-GlintPathData 10 } "glint"

# --- New-DragonStop: bakes a 0..1 alpha into an #AARRGGBB gradient stop ---
$s = New-DragonStop '#F97316' 0.5 0.25
Assert-Eq $s.Offset 0.25 "offset passthrough"
Assert-Eq $s.Color.A 128 "alpha 0.5 -> 128"
Assert-Eq $s.Color.R 249 "R from F9"
Assert-Eq $s.Color.G 115 "G from 73"
Assert-Eq $s.Color.B 22  "B from 16"
Assert-Eq (New-DragonStop '#FFFFFF' 0 0).Color.A 0   "alpha 0 -> 0"
Assert-Eq (New-DragonStop '#FFFFFF' 1 1).Color.A 255 "alpha 1 -> 255"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
