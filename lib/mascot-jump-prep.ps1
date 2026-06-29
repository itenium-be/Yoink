# Phase 1: look around in the slot, then hand off. Records the slot and the
# top-edge landing positions on $box (window coords) for the jump to animate.
$LookingSize = 103   # rendered height (px); reproduces the original looking scale

function Start-JumpPrep {
  param([hashtable]$Box, [scriptblock]$OnDone)
  $win = $Box.Win; $slot = $Box.Slot; $m = $Box.Mascot
  $m.Height = $LookingSize
  $p = $slot.TransformToVisual($win).Transform([System.Windows.Point]::new(0, 0))
  $Box.SlotLeft = $p.X; $Box.SlotTop = $p.Y
  # Land straddling the card's top edge, straight above the slot (vertical only).
  $cardTop = $Box.Card.TransformToVisual($win).Transform([System.Windows.Point]::new(0, 0)).Y
  $Box.TopLeft = $p.X; $Box.TopTop = $cardTop - ($m.Height * 0.72) - 30
  [System.Windows.Controls.Canvas]::SetLeft($m, $Box.SlotLeft)
  [System.Windows.Controls.Canvas]::SetTop($m, $Box.SlotTop)
  Start-Flipbook -Image $m -Dir (Join-Path $PSScriptRoot '..\mascots\looking') -Size $LookingSize -OnDone $OnDone
}
