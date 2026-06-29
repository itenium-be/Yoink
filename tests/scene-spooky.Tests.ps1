. "$PSScriptRoot\..\lib\scene-spooky.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# Corner web: anchor (0,0), radius 100, 3 spokes across 0..90deg, 2 ring threads.
# Spoke angles 0,45,90 -> tips (100,0) (70.71,70.71) (0,100).
$d = New-WebPathData 0 0 100 3 2

Assert-True ($d.StartsWith('M')) "web path starts with M (moveto)"
Assert-True ($d.Contains('M 0,0 L 100,0')) "spoke 0deg runs origin -> (100,0)"
Assert-True ($d.Contains('L 0,100')) "spoke 90deg tip at (0,100)"
Assert-True ($d.Contains('70.71,70.71')) "spoke 45deg tip at (70.71,70.71)"
# One 'M 0,0 ' move per spoke (ring threads start elsewhere).
Assert-Eq ([regex]::Matches($d, 'M 0,0 ').Count) 3 "one move per spoke"
# 2 ring threads, each an M..L..L polyline across 3 spokes -> 2 'L' per ring + spoke Ls.
Assert-True ($d.Contains('33.33,0')) "inner ring crosses spoke 0 at r=33.33"

# Invariant decimals: XAML needs '.', NOT the ',' an nl-BE locale emits.
Assert-True ($d.Contains('70.71')) "uses '.' decimal separator"
Assert-True (-not $d.Contains('70,71')) "does not use ',' decimal separator"

# Degenerate inputs are coerced, never throw / loop forever.
$d2 = New-WebPathData 0 0 50 1 0
Assert-True ($d2.StartsWith('M')) "spokes<2 / rings<1 still yields a path"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
