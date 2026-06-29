# Phase 1: look around in the slot, then hand off. Computes the resting (slot)
# and landing (top-edge) positions on $box. Positions anchor the creature by its
# feet + torso-centre (baked into the normalized frames), so every phase lines up.
function Start-JumpPrep {
  param([hashtable]$Box, [scriptblock]$OnDone)
  $win = $Box.Win; $slot = $Box.Slot; $m = $Box.Mascot
  $sp = $slot.TransformToVisual($win).Transform([System.Windows.Point]::new(0, 0))
  $slotCx = $sp.X + $slot.ActualWidth / 2
  $slotBottom = $sp.Y + $slot.ActualHeight
  $cardTop = $Box.Card.TransformToVisual($win).Transform([System.Windows.Point]::new(0, 0)).Y
  $ax = $Box.AnchorX * $Box.MascotW   # px from image left to torso centre
  $ay = $Box.AnchorY * $Box.MascotH   # px from image top to feet baseline

  # Rest: stand in the slot. Land: feet on the card's top edge, raised a touch.
  $Box.RestLeft = $slotCx - $ax
  $Box.RestTop  = $slotBottom - $ay
  $Box.LandTop  = ($cardTop - 3) - $ay   # feet just above the edge; straight up -> same left

  [System.Windows.Controls.Canvas]::SetLeft($m, $Box.RestLeft)
  [System.Windows.Controls.Canvas]::SetTop($m, $Box.RestTop)
  Start-Flipbook -Image $m -Dir (Join-Path $PSScriptRoot '..\mascots\looking') -OnDone $OnDone
}
