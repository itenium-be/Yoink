# Phase 3 (needs-input): loop the flag wave on the top edge until dismissed.
$FlagSize = 150   # flag frames carry the flag around the character; tune to match looking

function Start-FlagWave {
  param([hashtable]$Box)
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\flag') -Size $FlagSize -Loop
}
