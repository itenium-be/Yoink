. "$PSScriptRoot\..\lib\scene-waves.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# width=20, period=8, amp=2, top=10.5, bottom=30, step=5 -> samples x=0,5,10,15,20 (5 pts)
$d = New-WavePathData 20 8 2 10.5 30 5

Assert-True ($d.StartsWith('M')) "path starts with M (moveto)"
Assert-True ($d.TrimEnd().EndsWith('Z')) "path is closed with Z"
# 4 crest line segments (pts 2..5) + 2 closing corners = 6 'L ' tokens
Assert-Eq ([regex]::Matches($d, 'L ').Count) 6 "expected line-segment count"
# Invariant decimals: XAML needs '.', NOT the ',' a Belgian (nl-BE) locale would emit
Assert-True ($d.Contains('10.5')) "uses '.' decimal separator"
Assert-True (-not $d.Contains('10,5')) "does not use ',' decimal separator"

# step<=0 is coerced to a safe default (no infinite loop, still produces a path)
$d2 = New-WavePathData 12 6 1 5 20 0
Assert-True ($d2.StartsWith('M')) "step<=0 still yields a path"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
