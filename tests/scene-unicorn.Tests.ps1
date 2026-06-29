. "$PSScriptRoot\..\lib\scene-unicorn.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# Dome arc over the card top. center (100,100), r=50, sweep 180deg->360deg, step 90deg
# -> angles 180,270,360 -> points (50,100) (100,50) (150,100): a rainbow arch (y-down).
$d = New-ArcPathData 100 100 50 180 360 90

Assert-True ($d.StartsWith('M')) "arc path starts with M (moveto)"
# An arc is a stroked open polyline, NOT a filled shape: it must NOT be closed.
Assert-True (-not $d.Contains('Z')) "arc path is open (no Z)"
Assert-True ($d.Contains('M 50,100')) "first point at angle 180 (left of dome)"
Assert-True ($d.Contains('L 150,100')) "last point at angle 360 (right of dome)"
Assert-True ($d.Contains('100,50')) "apex point at angle 270 (top of dome)"
# 3 sampled points -> 2 line segments
Assert-Eq ([regex]::Matches($d, 'L ').Count) 2 "expected line-segment count"

# Invariant decimals: XAML needs '.', NOT the ',' a Belgian (nl-BE) locale would emit.
$f = New-ArcPathData 0 0 10 0 90 30
Assert-True ($f.Contains('8.66')) "uses '.' decimal separator"
Assert-True (-not $f.Contains('8,66')) "does not use ',' decimal separator"

# step<=0 is coerced to a safe default (no infinite loop, still a path).
$d2 = New-ArcPathData 0 0 10 180 360 0
Assert-True ($d2.StartsWith('M')) "step<=0 still yields a path"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
