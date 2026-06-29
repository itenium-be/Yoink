# Phase 3 (needs-input): loop the flag wave at the right end until dismissed.
function Start-FlagWave {
  param([hashtable]$Box)
  Set-MascotClip $Box 'flag' $Box.FxRight $Box.FyLand | Out-Null
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\flag') -Loop
}
