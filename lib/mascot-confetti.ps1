# Phase 3 (done): loop confetti on the top edge until dismissed.
function Start-Confetti {
  param([hashtable]$Box)
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\confetti') -Loop
}
