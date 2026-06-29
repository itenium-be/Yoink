# Position the mascot for a given clip so its feet + torso-centre anchor lands at
# the window point (Fx, Fy). Clips can have different canvases (spare clips like gym
# and horizontal-jump each have their own): sizing every clip by the shared
# DisplayScale keeps the creature the same on-screen size, and feet-anchoring keeps
# it put when one phase hands off to another. Returns the px offsets used.
function Set-MascotClip {
  param([hashtable]$Box, [string]$Clip, [double]$Fx, [double]$Fy)
  $g = $Box.Geom[$Clip]; $ds = $Box.DisplayScale; $m = $Box.Mascot
  $m.Height = $ds * $g.H            # Stretch=Uniform -> width follows canvas aspect
  $ax = $g.AX * $ds * $g.W
  $ay = $g.AY * $ds * $g.H
  [System.Windows.Controls.Canvas]::SetLeft($m, $Fx - $ax)
  [System.Windows.Controls.Canvas]::SetTop($m, $Fy - $ay)
  return @{ Ax = $ax; Ay = $ay }
}
