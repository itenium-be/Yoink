# Phase 3 (experimental, replaces confetti): the creature works out at the right end.
function Start-Gym {
  param([hashtable]$Box)
  Set-MascotClip $Box 'gym' $Box.FxRight $Box.FyLand | Out-Null
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\gym') -Loop
}
