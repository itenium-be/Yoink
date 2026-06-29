# Phase 3 (done): loop confetti at the right end until dismissed.
function Start-Confetti {
  param([hashtable]$Box)
  Set-MascotClip $Box 'confetti' $Box.FxRight $Box.FyLand | Out-Null
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\confetti') -Loop
}
