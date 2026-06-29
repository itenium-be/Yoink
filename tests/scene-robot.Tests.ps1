Add-Type -AssemblyName PresentationCore, WindowsBase
. "$PSScriptRoot\..\lib\scene-robot.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# An OPEN XAML polyline (a circuit trace) with invariant (space-separated, '.')
# coordinates that WPF parses, also under the nl-BE comma-decimal machine locale.
function Assert-OpenGeometry($fn, $msg) {
  $d = & $fn
  Assert-True ($d.StartsWith('M')) "$msg starts with M"
  Assert-True (-not $d.Contains(',')) "$msg no ',' (space-separated, invariant decimals)"
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

# --- New-TracePathData: right-angle polyline from an ordered point list ---
$pts = @(@(0, 0), @(10.5, 0), @(10.5, 5.25), @(20, 5.25))
Assert-OpenGeometry { New-TracePathData $pts } "trace"
Assert-Eq (New-TracePathData @(@(1, 2), @(3, 4))) 'M 1 2 L 3 4' "trace two-point string"
Assert-Eq (New-TracePathData @(@(10.5, 2.25), @(0, 0))) 'M 10.5 2.25 L 0 0' "trace fractional invariant '.'"

# --- New-RobotStop: bakes a 0..1 alpha into an #AARRGGBB gradient stop ---
$s = New-RobotStop '#22D3EE' 0.5 0.25
Assert-Eq $s.Offset 0.25 "offset passthrough"
Assert-Eq $s.Color.A 128 "alpha 0.5 -> 128"
Assert-Eq $s.Color.R 34  "R from 22"
Assert-Eq $s.Color.G 211 "G from D3"
Assert-Eq $s.Color.B 238 "B from EE"
Assert-Eq (New-RobotStop '#FFFFFF' 0 0).Color.A 0   "alpha 0 -> 0"
Assert-Eq (New-RobotStop '#FFFFFF' 1 1).Color.A 255 "alpha 1 -> 255"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
