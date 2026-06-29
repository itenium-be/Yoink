Add-Type -AssemblyName PresentationCore, WindowsBase
. "$PSScriptRoot\..\lib\scene-dragon.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# --- New-FlamePathData: one flame tongue as XAML geometry ---
$d = New-FlamePathData 13 20

Assert-True ($d.StartsWith('M')) "flame path starts with M (moveto)"
Assert-True ($d.TrimEnd().EndsWith('Z')) "flame path is closed with Z"
# Coordinates are space-separated, so any ',' would be a comma-decimal locale leak.
Assert-True (-not $d.Contains(',')) "no ',' (space-separated coords, invariant decimals)"
Assert-True ($d.Contains('.')) "uses '.' decimal separator"
$parsed = $null
try { $parsed = [System.Windows.Media.Geometry]::Parse($d) } catch { }
Assert-True ($null -ne $parsed) "Geometry.Parse accepts the flame path"

# Under a comma-decimal culture (machine is nl-BE) it must still emit '.' and parse.
$prev = [System.Threading.Thread]::CurrentThread.CurrentCulture
try {
  [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('nl-BE')
  $dc = New-FlamePathData 13 20
  Assert-True (-not $dc.Contains(',')) "nl-BE: still no ',' decimal"
  $pc = $null; try { $pc = [System.Windows.Media.Geometry]::Parse($dc) } catch { }
  Assert-True ($null -ne $pc) "nl-BE: Geometry.Parse still accepts the flame path"
} finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $prev }

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
