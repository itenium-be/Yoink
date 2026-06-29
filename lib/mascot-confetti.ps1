# Phase 3 (done): loop confetti on the top edge until dismissed.
$ConfettiSize = 150   # confetti frames carry particle effects around the character; tune to match looking

function Start-Confetti {
  param([hashtable]$Box)
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\confetti') -Size $ConfettiSize -Loop
}
