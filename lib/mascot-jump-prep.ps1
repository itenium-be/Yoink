# Phase 1: look around in the slot, then hand off. Records the feet points (window
# coords) the later phases anchor to: rest (in the slot), land (on the top edge),
# and the right end. Feet-based so clips with different canvases still line up.
function Start-JumpPrep {
  param([hashtable]$Box, [scriptblock]$OnDone)
  $win = $Box.Win; $slot = $Box.Slot
  $sp = $slot.TransformToVisual($win).Transform([System.Windows.Point]::new(0, 0))
  $slotCx = $sp.X + $slot.ActualWidth / 2
  $slotBottom = $sp.Y + $slot.ActualHeight
  $cardLeft = $Box.Card.TransformToVisual($win).Transform([System.Windows.Point]::new(0, 0)).X
  $cardTop = $Box.Card.TransformToVisual($win).Transform([System.Windows.Point]::new(0, 0)).Y
  $cardRight = $cardLeft + $Box.Card.ActualWidth

  $Box.FxLeft = $slotCx
  $Box.FyRest = $slotBottom
  $Box.FyLand = $cardTop - 3                              # feet just above the edge
  $Box.FxRight = $cardRight - ($slotCx - $cardLeft)       # right end mirrors the slot inset

  Set-MascotClip $Box 'looking' $Box.FxLeft $Box.FyRest | Out-Null
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\looking') -OnDone $OnDone
}
