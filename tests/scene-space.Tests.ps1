Add-Type -AssemblyName PresentationCore, WindowsBase
. "$PSScriptRoot\..\lib\scene-space.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}

# New-SpaceStop bakes a 0..1 alpha into an #AARRGGBB gradient stop.
$s = New-SpaceStop '#7C3AED' 0.5 0.25
Assert-Eq $s.Offset 0.25 "offset passthrough"
Assert-Eq $s.Color.A 128 "alpha 0.5 -> 128"
Assert-Eq $s.Color.R 124 "R from 7C"
Assert-Eq $s.Color.G 58  "G from 3A"
Assert-Eq $s.Color.B 237 "B from ED"

Assert-Eq (New-SpaceStop '#FFFFFF' 0 0).Color.A 0   "alpha 0 -> 0"
Assert-Eq (New-SpaceStop '#FFFFFF' 1 1).Color.A 255 "alpha 1 -> 255"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
