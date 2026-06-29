# Phase 2: play the jump frames while translating straight up onto the top edge.
$JumpSize = 197   # the jump sprite's character fills ~half its frame, so it needs a taller box to match

function Start-Jump {
  param([hashtable]$Box, [scriptblock]$OnDone)
  $m = $Box.Mascot
  $dur = [System.Windows.Duration][TimeSpan]::FromMilliseconds(700)
  $up = New-Object System.Windows.Media.Animation.DoubleAnimation $Box.SlotTop, $Box.TopTop, $dur
  $m.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $up)
  Start-Flipbook -Image $m -Dir (Join-Path $PSScriptRoot '..\mascots\jump') -Size $JumpSize -OnDone {
    # Pin the final position so the looped celebrate phase stays on the top edge.
    $m.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $null)
    [System.Windows.Controls.Canvas]::SetTop($m, $Box.TopTop)
    if ($OnDone) { & $OnDone }
  }.GetNewClosure()
}
