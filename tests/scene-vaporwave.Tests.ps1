. "$PSScriptRoot\..\lib\scene-vaporwave.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# Perspective grid: width 100, horizon y=60, bottom y=200, 3 columns, 2 rows,
# vanishing point x=50. Bottom xs = 0, 33.33, 66.67, 100 (cols+1 verticals).
# Horizontal rows tighten toward the horizon: y = 60 + 140 * (r/rows)^2.
#   r=1 -> 60 + 140*0.25 = 95 ; r=2 -> 60 + 140 = 200.
$d = New-GridPathData 100 60 200 3 2 50

Assert-True ($d.StartsWith('M')) "grid path starts with M (moveto)"
Assert-True ($d.Contains('M 50,60 L 0,200')) "left vertical: vanishing point -> bottom-left"
Assert-True ($d.Contains('L 100,200')) "right vertical reaches bottom-right (100,200)"
Assert-True ($d.Contains('33.33,200')) "interior vertical hits bottom at x=33.33"
Assert-True ($d.Contains('66.67,200')) "interior vertical hits bottom at x=66.67"
Assert-True ($d.Contains('M 0,95 L 100,95')) "near-horizon row tightened to y=95"
Assert-True ($d.Contains('M 0,200 L 100,200')) "front row at the bottom edge"
# One 'M 50,60 ' move per vertical line (cols+1 = 4).
Assert-Eq ([regex]::Matches($d, 'M 50,60 ').Count) 4 "one move per vertical (cols+1)"

# Invariant decimals: XAML needs '.', NOT the ',' an nl-BE locale emits.
Assert-True ($d.Contains('33.33')) "uses '.' decimal separator"
Assert-True (-not $d.Contains('33,33')) "does not use ',' decimal separator"

# Degenerate inputs are coerced, never throw / divide by zero.
$d2 = New-GridPathData 100 50 150 0 0 50
Assert-True ($d2.StartsWith('M')) "cols<1 / rows<1 still yields a path"

# Mountain ridge: closed silhouette across width 100, base y=80, peak y=20, 2 peaks.
# Peak p spans w/peaks; apex at its centre (peakY), valley at its right edge (baseY).
#   p=0 -> apex (25,20), valley (50,80) ; p=1 -> apex (75,20), valley (100,80).
$m = New-MountainPathData 100 80 20 2
Assert-True ($m.StartsWith('M 0,80')) "mountain path starts at the left base (0,80)"
Assert-True ($m.EndsWith('Z'))        "mountain path is closed (filled silhouette ends with Z)"
Assert-True ($m.Contains('L 25,20'))  "first apex at peakY (25,20)"
Assert-True ($m.Contains('L 75,20'))  "second apex at peakY (75,20)"
Assert-True ($m.Contains('L 50,80'))  "interior valley returns to baseY (50,80)"
Assert-True ($m.Contains('L 100,80')) "ridge spans the full width back to base"

# Invariant decimals: a 3-peak ridge puts the first apex at 100*0.5/3 = 16.67.
$m2 = New-MountainPathData 100 80 20 3
Assert-True ($m2.Contains('16.67')) "uses '.' decimal separator"
Assert-True (-not $m2.Contains('16,67')) "does not use ',' decimal separator"

# Degenerate peaks are coerced, never loop forever.
$m3 = New-MountainPathData 100 80 20 0
Assert-True ($m3.StartsWith('M')) "peaks<1 still yields a path"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
