# Phase 2: play the jump frames while translating straight up onto the top edge.
function Start-Jump {
  param([hashtable]$Box, [scriptblock]$OnDone)
  $m = $Box.Mascot
  $dur = [System.Windows.Duration][TimeSpan]::FromMilliseconds(700)
  $up = New-Object System.Windows.Media.Animation.DoubleAnimation $Box.RestTop, $Box.LandTop, $dur
  $m.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $up)
  Start-Flipbook -Image $m -Dir (Join-Path $PSScriptRoot '..\mascots\jump') -OnDone {
    # Pin the final position so the looped celebrate phase stays on the top edge.
    $m.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $null)
    [System.Windows.Controls.Canvas]::SetTop($m, $Box.LandTop)
    if ($OnDone) { & $OnDone }
  }.GetNewClosure()
}
