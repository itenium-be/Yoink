# Phase 3 (needs-input): loop the flag wave on the top edge until dismissed.
function Start-FlagWave {
  param([hashtable]$Box)
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\flag') -Loop
}
