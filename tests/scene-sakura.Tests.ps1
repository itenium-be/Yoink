Add-Type -AssemblyName PresentationCore, WindowsBase
. "$PSScriptRoot\..\lib\scene-sakura.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# --- New-PetalPathData: one cherry-blossom petal as XAML geometry ---
$d = New-PetalPathData 11 14

Assert-True ($d.StartsWith('M')) "petal path starts with M (moveto)"
Assert-True ($d.TrimEnd().EndsWith('Z')) "petal path is closed with Z"
# Coordinates are space-separated, so any ',' would be a comma-decimal locale leak.
Assert-True (-not $d.Contains(',')) "no ',' (space-separated coords, invariant decimals)"
Assert-True ($d.Contains('.')) "uses '.' decimal separator"
# It must parse as real WPF geometry.
$parsed = $null
try { $parsed = [System.Windows.Media.Geometry]::Parse($d) } catch { }
Assert-True ($null -ne $parsed) "Geometry.Parse accepts the petal path"

# Under a comma-decimal culture (machine is nl-BE) it must still emit '.' and parse.
$prev = [System.Threading.Thread]::CurrentThread.CurrentCulture
try {
  [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('nl-BE')
  $dc = New-PetalPathData 11 14
  Assert-True (-not $dc.Contains(',')) "nl-BE: still no ',' decimal"
  $pc = $null; try { $pc = [System.Windows.Media.Geometry]::Parse($dc) } catch { }
  Assert-True ($null -ne $pc) "nl-BE: Geometry.Parse still accepts the petal path"
} finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $prev }

# --- New-SakuraStop: bakes a 0..1 alpha into an #AARRGGBB gradient stop ---
$s = New-SakuraStop '#FBC2EB' 0.5 0.25
Assert-Eq $s.Offset 0.25 "offset passthrough"
Assert-Eq $s.Color.A 128 "alpha 0.5 -> 128"
Assert-Eq $s.Color.R 251 "R from FB"
Assert-Eq $s.Color.G 194 "G from C2"
Assert-Eq $s.Color.B 235 "B from EB"
Assert-Eq (New-SakuraStop '#FFFFFF' 0 0).Color.A 0   "alpha 0 -> 0"
Assert-Eq (New-SakuraStop '#FFFFFF' 1 1).Color.A 255 "alpha 1 -> 255"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
